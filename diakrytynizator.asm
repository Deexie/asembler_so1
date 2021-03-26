SYS_READ        equ 0
SYS_WRITE       equ 1
SYS_EXIT        equ 60

STDIN           equ 0
STDOUT          equ 1

ASCII_ZERO      equ 48
MODULO          equ 0x10FF80
BUFFER_SIZE     equ 2048

INDEX_4B        equ 0
INDEX_3B        equ 1
INDEX_2B        equ 2
INDEX_NEXT_B    equ 3

global _start

section .data

i_buf_pos:          dw 0
o_buf_pos:          dw 0
i_buf_size:         dw 0

; Greatest numbers that can be coded in UTF-8 using respectively 1, 2, 3 or 4 bytes.
last_codes:
        dd 0x007F
        dd 0x07FF
        dd 0xFFFF
        dd 0x10FFFF

; Numbers that have bits '1' only on a few lowest positions.
last_bits:
        dq 0x7                              ; 3 last bits
        dq 0xF                              ; 4 last bits
        dq 0x1F                             ; 5 last bits
        dq 0x3F                             ; 6 last bits

; Templates for UTF-8 encoding structure.
masks:
        db 0xF0                             ; MASK_4B           - 11110000
        db 0xE0                             ; MASK_3B           - 11100000
        db 0xC0                             ; MASK_2B           - 11000000
        db 0x80                             ; NEXT_BYTES_MASK   - 10000000

section .bss
argc            resb 8
arg_pos         resb 8

i_buffer        resb BUFFER_SIZE
o_buffer        resb BUFFER_SIZE

current_byte    resb 1
current_sign    resb 4
sign_size       resb 1

section .text

; Reads to i_buffer from standard input.
; Modifies rax, rdi, rsi and rdx registers.
read:
        xor     ax, ax
        mov     [i_buf_pos], ax

        mov     rax, SYS_READ
        mov     rdi, STDIN
        mov     rsi, i_buffer
        mov     rdx, BUFFER_SIZE
        syscall

        cmp     rax, 0
        jl      exit_failure

        mov     [i_buf_size], ax

        ret

; Writes content of o_buffer to standard output.
; Modifies rax, rdi, rsi and rdx registers.
write:
        xor     rdx, rdx
        mov     rax, SYS_WRITE
        mov     rdi, STDOUT
        mov     rsi, o_buffer
        mov     dx, [o_buf_pos]
        syscall

        cmp     ax, [o_buf_pos]
        jne     exit_failure

        xor     di, di
        mov     [o_buf_pos], di             ; Starting from the beginning of the buffer.

        ret

; Checks if number given in rdi was encoded in the shortest possible way.
; Modifies rsi and rdi registers.
check_if_lowest:
        mov     rsi, [sign_size]
        sub     rsi, 2                      ; Index of last code of shorter sign.

        cmp     edi, [last_codes + 4 * rsi]
        jle     exit_failure
        inc     rsi                         ; Index of last code of that sign.
        cmp     edi, [last_codes + 4 * rsi]
        jg      exit_failure

        ret

; Reads byte and adds it to [current_sign].
; Returns in rax 0 if operation executed successfully and 1 otherwise.
; Modifies rax, rdi, rsi registers.
get_byte:
        mov     di, [i_buf_pos]
        mov     si, [i_buf_size]
        cmp     di, si
        jnz     add_it                      ; Checks if another byte from i_buffer can be read.
        call    read

        test    rax, rax
        jnz     add_it                      ; Checks if there are any bytes to read from stdin.
        mov     rax, 1                      ; Returns 1 if no more bytes can be read.
        ret

add_it:
        xor     rdx, rdx
        xor     rax, rax
        mov     ax, [i_buf_pos]
        mov     dl, [i_buffer + rax]        ; Gets appropriate byte.
        inc     rax
        mov     [i_buf_pos], ax             ; One byte from i_buffer was read.
        mov     [current_byte], dl

        xor     rax, rax
        ret

; Converts one byte to proper UTF-8 code depending on its position in sign.
; In rdi it gets a number, that is being encoded, right-shifted so that a few (rsi + 3) last
; bits of it combined with a proper template are a byte of the number encoded in UTF-8.
; In rsi it gets number of bits that are to be shifted lowered by 3 (for proper indexation).
; Returns encoded byte in rax. Shifts rdi so that it holds the rest of bits.
; Modifies rdi, rax and rcx registers.
encode_byte:
        mov     rax, rdi
        and     rax, [last_bits + rsi * 8]  ; Gets the proper number of last bits.
        add     al, [masks + rsi]           ; Combines it with a proper mask.

        mov     rcx, rsi
        add     rcx, 3
        shr     rdi, cl
        ret

; Encodes number given in rdi to UTF-8 sign.
; Modifies rax, rdx, rdi, rsi and r8-r11 registers.
encode:
        xor     rdx, rdx
        cmp     edi, [last_codes]           ; Can be encoded on 1 byte.
        jle     enc_1B
        cmp     edi, [last_codes + 4]       ; Can be encoded on 2 bytes.
        jle     enc_2B
        cmp     edi, [last_codes + 8]       ; Can be encoded on 3 bytes.
        jle     enc_3B
        cmp     edi, [last_codes + 12]      ; Can be encoded on 4 bytes.
        jle     enc_4B

        jmp     exit_failure

enc_1B:
        mov     dx, [o_buf_pos]
        mov     [o_buffer + rdx], dil
        inc     dx
        mov     [o_buf_pos], dx
        ret

enc_2B:
        xor     r8, r8
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r8b, al

        xor     r9, r9
        mov     rsi, INDEX_2B
        call    encode_byte
        mov     r9b, al                     ; Encodes bytes of 2-bytes sign.

        mov     dx, [o_buf_pos]
        jmp     write_2B

enc_3B:
        xor     r8, r8
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r8b, al

        xor     r9, r9
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r9b, al

        xor     r10, r10
        mov     rsi, INDEX_3B
        call    encode_byte
        mov     r10b, al                    ; Encodes bytes of 3-bytes sign.

        mov     dx, [o_buf_pos]
        jmp     write_3B

enc_4B:
        xor     r8, r8
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r8b, al

        xor     r9, r9
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r9b, al

        xor     r10, r10
        mov     rsi, INDEX_NEXT_B
        call    encode_byte
        mov     r10b, al

        xor     r11, r11
        mov     rsi, INDEX_4B
        call    encode_byte
        mov     r11b, al                    ; Encodes bytes of 4-bytes sign.

        mov     dx, [o_buf_pos]

write_4B:
        mov     [o_buffer + rdx], r11
        inc     dx
write_3B:
        mov     [o_buffer + rdx], r10b
        inc     dx
write_2B:
        mov     [o_buffer + rdx], r9b
        inc     dx
        mov     [o_buffer + rdx], r8b
        inc     dx
        mov     [o_buf_pos], dx             ; Puts proper bytes into o_buffer.

        ret

; Reads sign (1 - 4 bytes) from i_buffer, checks its validity and converts it to number.
; Returns computed number in rax.
; Modifies rax, rbx, rdx, rdi, r12 registers.
get_sign:
       xor      rax, rax
       mov      [current_sign], rax

       call     get_byte
       test     rax, rax
       jnz      exit_success                ; All stdin has been read.

       xor      r12, r12                    ; Stores sign size.
       xor      rax, rax
       mov      al, [current_byte]

       mov      dl, al
       test     dl, 0x80                    ; 10000000 - checks if byte starts with 0.
       jz       sign_1B

       mov      dl, al
       and      dl, 0xE0                    ; 11100000 - checks if byte starts with 110.
       cmp      dl, [masks + INDEX_2B]
       je       sign_2B

       mov      dl, al
       and      dl, 0xF0                    ; 11110000 - checks if byte starts with 1110.
       cmp      dl, [masks + INDEX_3B]
       je       sign_3B

       mov      dl, al
       and      dl, 0xF8                    ; 11111000 - checks if byte starts with 11110.
       cmp      dl, [masks + INDEX_4B]
       je       sign_4B

       jmp      exit_failure                ; Invalid first byte of sign.

; Sets needed properties and parses first byte (to rdx) depending on sign size.
sign_1B:
        add     [current_sign], al
        mov     r12b, 1
        mov     [sign_size], r12b
        ret
sign_2B:
        mov     dl, al
        sub     dl, [masks + INDEX_2B]
        add     [current_sign], dl
        mov     r12b, 2

        jmp     later_bytes
sign_3B:
        mov     dl, al
        sub     dl, [masks + INDEX_3B]
        add     [current_sign], dl
        mov     r12b, 3

        jmp     later_bytes
sign_4B:
        mov     dl, al
        sub     dl, [masks + INDEX_4B]
        add     [current_sign], dl
        mov     r12b, 4

later_bytes:
        mov     [sign_size], r12b
        dec     r12b                        ; First byte was already parsed.
        mov     rbx, rdx

sign_loop:

        call    get_byte
        test    rax, rax
        jnz     exit_failure                ; Cannot read next byte.

        mov     al, [current_byte]
        xor     rdx, rdx
        mov     dl, al
        and     dl, 0xC0                    ; 11000000 - checks if byte starts with 10.
        cmp     dl, [masks + INDEX_NEXT_B]
        jne     exit_failure                ; Invalid byte read.

        mov     dl, al
        sub     dl, [masks + INDEX_NEXT_B]  ; Now dl contains encrypted byte.

        shl     rbx, 6
        add     rbx, rdx                    ; Now rbx contains concatenation of already parsed bytes.

        dec     r12b
        test    r12b, r12b
        jnz     sign_loop

        mov     rdi, rbx
        call    check_if_lowest

        mov     [current_sign], rbx
        mov     rax, rbx
        ret

; Converts string to number.
; Gets string in rdi and its first character in rsi.
; Returns the number in rax.
string_to_number:
        sub     rsi, ASCII_ZERO
        jl      exit_failure                ; If lower than 0 then exit with code 1.
        cmp     rsi, 9
        jg      exit_failure                ; If grater than 9 then exit with code 1.

        imul    rax, 10
        add     rax, rsi

        inc     rdi
        mov     sil, [rdi]
        test    rsi, rsi
        jnz     string_to_number
        ret

; Counts polynomial value.
; Gets x in rdi and pointer to n-th coefficient in rsi.
; Returns result in rax.
polynomial:
        mov     rax, [argc]
        mov     [arg_pos], rax              ; Last coefficient.
        mov     r9, MODULO

        xor     rax, rax
polynomial_loop:
        xor     rdx, rdx
        imul    rax, rdi
        div     r9
        mov     rax, rdx                    ; Multiplies by x.

        xor     rdx, rdx
        add     rax, [rsi]
        div     r9
        mov     rax, rdx                    ; Adds this coefficient.

        sub     rsi, 8                      ; Next coefficient.

        mov     rdx, [arg_pos]
        dec     rdx
        mov     [arg_pos], rdx
        test    rdx, rdx
        jnz     polynomial_loop

        ret

_start:
        mov     rax, [rsp]
        dec     rax                         ; Path is not counted.
        mov     [argc], rax

        test    rax, rax
        jz      exit_failure                ; Exits due to no args.

        mov     rax, 0
        mov     [arg_pos], rax

        lea     rbp, [rsp + 16]             ; args[1]

convert_args:
        mov     rdi, [rbp]
        mov     sil, [rdi]
        mov     rax, 0

        call    string_to_number

        mov     [rbp], rax
        add     rbp, 8                      ; Next arg.
        mov     rax, [arg_pos]
        inc     rax
        mov     [arg_pos], rax
        cmp     rax, [argc]                 ; Checks if there are pther args left.
        jne     convert_args

process_input:
        call    get_sign

        cmp     rax, 0x80                   ; Does not need to be revalued.
        jl      to_utf

        mov     rdi, rax
        sub     rdi, 0x80
        lea     rsi, [rbp - 8]
        call    polynomial
        add     rax, 0x80                   ; Counts new value.

to_utf:
        mov     rdi, rax
        call    encode

        xor     rax, rax
        mov     ax, [o_buf_pos]
        add     rax, 4
        cmp     rax, BUFFER_SIZE
        jl      process_input               ; Checks if o_buffer has enough free space.
        call    write
        jmp     process_input

exit_failure:
        mov     r15, 1
        jmp     exit

exit_success:
        xor     r15, r15
        jmp     exit

; Exits program with code given in r15.
exit:
        xor     rax, rax
        mov     ax, [o_buf_pos]
        test    ax, ax                      ; Check if o_buffer is empty.
        jz      empty_buffer
        call    write
empty_buffer:
        mov     rax, SYS_EXIT
        mov     rdi, r15
        syscall