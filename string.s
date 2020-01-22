; Copyright 2015 Nicole Mazzuca <mazzucan@outlook.com>
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;     http://www.apache.org/licenses/LICENSE-2.0
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

global str_from_c_string
global str_print

global string_new
global string_from_str
global string_push_char
global string_push_str
global string_as_str
global string_delete

extern malloc
extern realloc
extern free
extern memcpy


; clobbers rax
%macro next_power_of_two 1
    dec %1           ; %1 should be a power of two
    mov rax, %1      ; so this makes %1 the next power of two
    shr rax, 1
    or %1, rax
    mov rax, %1
    shr rax, 2
    or %1, rax
    mov rax, %1
    shr rax, 4
    or %1, rax
    mov rax, %1
    shr rax, 8
    or %1, rax
    mov rax, %1
    shr rax, 16
    or %1, rax
    mov rax, %1
    shr rax, 32 
    or %1, rax
    inc %1
%endmacro

section .text

; struct string {
;     u8 *buf, [+0]
;     u64 length, [+8]
;     u64 capacity, [+16]
; }

; struct str {
;     u8 *buf, [+0]
;     u64 length, [+8]
; }


;; (u8 const *rdi) -> (str (rax, rdx))
;; rdi => the c_string to pass, to make into a str
;; ->
;; rax => .buf
;; rdx => .length
str_from_c_string:
    push rbp       ; function setup
    mov rbp, rsp

    mov rdx, -1    ; strlen(rdi) (without the zero)
    str_from_c_string_count_loop:
        inc rdx
        cmp byte [rdi + rdx], 0
        jnz str_from_c_string_count_loop

    ; rdx is already .len
    mov rax, rdi

    mov rsp, rbp
    pop rbp
    ret


;; (str (rax, rdx)) -> void
str_print:
    mov rsi, rax      ; read from rax
    ; rdx is already correct, len to read
    mov rax, 1        ; write syscall
    mov rdi, 1        ; stdout
    syscall
    ret



;; (hidden string *rdi) -> (string *rax)
;; rdi => where in memory you want the string to go
;; ->
;; rax => where in memory this function put the string (will be == to rdi from the beginning of the
;;        function)
string_new:
    mov qword [rdi], 0       ; .buf
    mov qword [rdi + 8], 0   ; .length
    mov qword [rdi + 16], 0  ; .capacity
    mov rax, rdi
    ret


;; (hidden string *rdi, str (rsi, rdx)) -> (string *rax)
;; rdi => where in memory you want the string to go
;; (rsi, rdx) => the str to convert from
;; ->
;; rax => where in memory this function put the string (will be == to rdi from the beginning of the
;;        function)
;;
;; r12 => .buf
;; r13 => .length
;; r14 => .capacity
;; r15 => pointer to struct
string_from_str:
    push rbp          ; function setup
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r13, rdx      ; rdx == str.length
    mov r14, rdx
    mov r15, rdi      ; rdi == hidden string placement

    next_power_of_two r14

    push rsi
    mov rdi, r14
    call malloc

    mov rdi, rax      ; dest (taken from malloc)
    pop rsi           ; src
    mov rdx, r13      ; n
    call memcpy
    mov r12, rax      ; string.buf

    mov [r15], r12
    mov [r15 + 8], r13
    mov [r15 + 16], r14

    pop r15
    pop r14
    pop r13
    pop r12
    mov rsp, rbp
    pop rbp
    ret


;; (string *rdi, char si) -> void
;; rdi => the string to push onto
;; rsi => the char to push onto the string ( truncated to 8 bits )
;;
;; r12 => .buf
;; r13 => .length
;; r14 => .capacity
;; r15 => pointer to struct
string_push_char:
    push rbp          ; function setup
    mov rbp, rsp
    push rsi
    ; rdi is already correct
    mov rsi, rsp
    mov rdx, 1
    call string_push_str
    mov rsp, rbp
    pop rbp


;; (string *rdi, str (rsi, rdx)) -> void
;; rdi => the string to push onto
;; rsi => the char to push onto the string ( truncated to 8 bits )
;;
;; r12 => .buf
;; r13 => .length
;; r14 => .capacity
;; r15 => pointer to struct
string_push_str:
    push rbp          ; function setup
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    push rdx          ; for memcpy (n)
    push rsi          ; for memcpy (src)

    mov r15, rdi
    mov r12, [r15]
    mov r13, [r15 + 8]
    mov r14, [r15 + 16]

    mov rax, r13
    add rax, rdx
    
    cmp r14, rax
    jl string_push_str_allocate
    cmp r14, 0
    je string_push_str_zero_sized_allocate

    string_push_str_push:
        mov rdi, r12      ; dest
        add rdi, r13      ; (+ initial string.len)
        pop rsi           ; src
        pop rdx           ; n
        add r13, rdx      ; (add str.len to string.len)
        call memcpy

    string_push_str_end:
        mov [r15], r12
        mov [r15 + 8], r13
        mov [r15 + 16], r14

        pop r15
        pop r14
        pop r13
        pop r12
        mov rsp, rbp
        pop rbp
        ret

    string_push_str_zero_sized_allocate:
        mov rax, 2
    string_push_str_allocate:
        mov r14, rax            ; string.cap = str.len + string.len
        next_power_of_two r14
        mov rdi, r12
        mov rsi, r14
        call realloc
        mov r12, rax
        jmp string_push_str_push


;; (string *rdi) -> str (rax, rdx)
;; rdi => the string to be turned into a str
string_as_str:
    mov rax, [rdi]
    mov rdx, [rdi + 8]
    ret


;; (string (stack)) -> void
;; (stack) => the string that will be freed
; [rsi + 0] => ret address
; [rsi + 8] => buf
; [rsi + 16] => len
; [rsi + 24] => cap
string_delete:
    mov rdi, [rsp + 8]
    jmp free

