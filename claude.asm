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

define read      3
define write     4
define close     6
define socket  359
define bind    361
define connect 362
define listen  363
define accept4 364

define PF_INET     2
define SOCK_STREAM 1

define BUFSZ 120

segment readable executable
start:
	sub esp, BUFSZ

	mov eax, socket
	mov ebx, PF_INET
	mov ecx, SOCK_STREAM
	xor edx, edx
	int 80h
	mov ebp, eax
	test eax, eax
	js  finish

	mov [esp], dword 0x901f0002
;	mov [esp], dword 0x50000002
	mov eax, bind
	mov ebx, ebp
	mov ecx, esp
	mov edx, 16
	int 80h
	test eax, eax
	js  finish

	mov eax, listen
	mov ecx, edx
	int 80h
	test eax, eax
	js  finish

.loop:
	mov eax, accept4
	mov ebx, ebp
	xor ecx, ecx
	xor edx, edx
	xor esi, esi
	int 80h
	mov edi, eax
	test eax, eax
	js  .loop

	mov eax, read
	mov ebx, edi
	mov ecx, esp
	mov edx, BUFSZ
	int 80h

	mov eax, write
	mov ecx, response
	mov edx, response.len
	int 80h

	mov eax, close
	int 80h

	jmp .loop

finish:
	xor eax, eax
	inc eax
	int 80h

response:
	db "HTTP/1.0 200 OK", 13, 10
	db "Content-Length: 8", 13, 10
	db 13, 10
	db "fuck off"
	.len = $ - response
