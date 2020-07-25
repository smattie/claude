;;; ----------------------------------------------------------------------------
;;; claude
;;;
;;; This work is free. You can redistribute it and/or modify it under the
;;; terms of the Do What The Fuck You Want To Public License, Version 2,
;;; as published by Sam Hocevar. See the COPYING file for more details.
;;;
;;; 2020/07 - smattie <https://github.com/smattie>
;;; ----------------------------------------------------------------------------

format elf executable 3
entry start

define fork        2
define read        3
define write       4
define open        5
define close       6
define waitpid     7
define alarm      27
define signal     48
define clone     120
define nanosleep 162
define sendfile  187
define socket    359
define bind      361
define connect   362
define listen    363
define accept4   364

define SIGALRM 14

define PF_INET     2
define SOCK_STREAM 1

define CLONE_VM      0x00000100
define CLONE_FS      0x00000200
define CLONE_FILES   0x00000400
define CLONE_SIGHAND 0x00000800
define CLONE_THREAD  0x00010000
define CLONE_SYSVSEM 0x00040000

THREADFLAGS = \
	CLONE_VM or CLONE_FILES  or CLONE_SIGHAND or \
	CLONE_FS or CLONE_THREAD or CLONE_SYSVSEM

define REQBUFSZ 1024
define CLIENTTIMEOUT 13

segment readable executable
start:
	sub esp, 64

	mov eax, socket
	mov ebx, PF_INET
	mov ecx, SOCK_STREAM
	xor edx, edx
	int 80h
	mov ebp, eax
	test eax, eax
	js  finish

	mov [esp], dword 0x901f0002 ;; af_inet, 8080
;	mov [esp], dword 0x50000002 ;; af_inet, 80
	mov eax, bind
	mov ebx, ebp
	mov ecx, esp
	mov  dl, 16
	int 80h
	test eax, eax
	js  finish

	mov eax, listen
	mov ecx, edx
	int 80h
	test eax, eax
	js  finish

	mov [esp], ebp       ;; XXX: esp/ecx is pointing at the top of the stack
	mov  al, clone       ;; which you usually wouldn't want but in this case
	mov ebx, THREADFLAGS ;; i don't *think* it matters
	mov ecx, esp
	xor edx, edx
	xor esi, esi
	xor edi, edi
	int 80h
	test eax, eax
	js  finish
	jz  waitthread

.loop:
	mov eax, accept4
	mov ebx, ebp
	xor ecx, ecx
	int 80h
	mov ebx, eax
	test eax, eax
	js  .loop

	mov eax, fork
	int 80h
	test eax, eax
	jz  serve
	jg  .close

.servererror:
	mov eax, write
	mov ecx, err500
	movzx edx, byte [ecx]
	inc ecx
	int 80h

.close:
	mov eax, close
	int 80h
	jmp .loop

;; ------------------------------------------------------------------
waitthread:
	mov eax, nanosleep ;; sleep ~3 seconds (presumably) if there
	mov ebx, esp       ;; are no children to be waited on
	xor ecx, ecx
	int 80h

	or  ebx, -1

.waitmore:
	mov eax, waitpid
	int 80h
	test eax, eax
	jns .waitmore
	jmp waitthread

;; ------------------------------------------------------------------
;; > ebx: client fd
;; > edi: 0
serve:
	sub esp, REQBUFSZ
	mov ebp, ebx

.newrequest:
	mov eax, signal
	mov ebx, SIGALRM
	mov ecx, alarmhandler
	int 80h

	mov eax, alarm
	mov ebx, CLIENTTIMEOUT
	int 80h

	mov esi, esp
	mov edx, REQBUFSZ

.readrequest:
	mov eax, read
	mov ebx, ebp
	mov ecx, esi
	int 80h

	mov edi, err400
	test eax, eax
	jle dropclient
	mov edi, err408

	sub edx, eax
	add esi, eax
	lea eax, [esi-4]
	mov eax, [eax]
	cmp eax, 0a0d0a0dh
	jne .readrequest

.getmethod:
	mov ecx, [esp]
	mov eax, alarm
	xor ebx, ebx
	int 80h

	or  edx, -1 ;; TODO: support head
;	mov edx, ecx
	xor ecx, 20544547h ;; get
	xor edx, 44414548h ;; head
	and ecx, edx       ;; good
	mov edi, err400    ;; advice
	jnz dropclient

	mov edi, esp
	add edi, 4

	;; assuming there is one space between method and
	;; uri, advance edi to the path for head requests
	test [esp], byte 8 ;; G=47h H=48h
	setnz cl
	add edi, ecx

.checkuri:
	mov ebx, index
	cmp [edi], word 202fh
	je  .sendfile

	;; TODO: parse path

	mov edi, err404
	jmp dropclient

.sendfile:
	mov edi, err500
	mov eax, open
	xor ecx, ecx
	xor edx, edx
	int 80h
	test eax, eax
	js  dropclient
	xor edi, edi

	mov ecx, eax
	mov eax, sendfile
	mov ebx, ebp
	or  esi, -1
	int 80h

	mov eax, close
	mov ebx, ecx
	int 80h
	jmp serve.newrequest

;; ------------------------------------------------------------------
;; > edi: err&
dropclient:
	mov ebx, ebp
	mov ecx, edi
	test edi, edi
	jz  @f

	movzx edx, byte [edi]

	mov eax, write
	inc ecx
	int 80h

@@:
	mov eax, close
	int 80h

;; ------------------------------------------------------------------
;; > ebx: status
finish:
	xor eax, eax
	inc eax
	int 80h

;; ------------------------------------------------------------------
alarmhandler:
	mov [esp], dword dropclient
	ret

;; ------------------------------------------------------------------
index:
	db "index.html", 0
	.len = $ - index

err400:
	db err400.len
	db "HTTP/1.1 400 Bad Request", 13, 10, 13, 10
	.len = $ - err400 - 1

err404:
	db err404.len
	db "HTTP/1.1 404 Not Found", 13, 10, 13, 10
	.len = $ - err404 - 1

err408:
	db err408.len
	db "HTTP/1.1 408 Request Timeout", 13, 10, 13, 10
	.len = $ - err408 - 1

err500:
	db err500.len
	db "HTTP/1.1 500 Internal Server Error", 13, 10, 13, 10
	.len = $ - err500 - 1
