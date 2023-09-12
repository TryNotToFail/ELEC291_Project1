$MODLP51RC2
org 0000H
   ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
TIMER2_RATE   EQU 1000    
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

DSEG at 0x30
	result: ds 4
	bcd: ds 5
	x: ds 4
	y: ds 4

BSEG
	mf: dbit 1	
	
CSEG
; These ’EQU’ must match the wiring between the microcontroller and ADC 
CE_ADC    EQU  P2.0 
MY_MOSI   EQU  P2.1  
MY_MISO   EQU  P2.2 
MY_SCLK   EQU  P2.3 
LCD_RS equ P3.2
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

$NOLIST
$include(LCD_4bit.inc)
$include(math32.inc)
$LIST

INIT_SPI: 
    setb MY_MISO    ; Make MISO an input pin 
    clr MY_SCLK     ; For mode (0,0) SCLK is zero 
    ret 
  
DO_SPI_G: 
    push acc 
    mov R1, #0      ; Received byte stored in R1 
    mov R2, #8      ; Loop counter (8-bits) 
DO_SPI_G_LOOP: 
    mov a, R0       ; Byte to write is in R0 
    rlc a           ; Carry flag has bit to write 
    mov R0, a 
    mov MY_MOSI, c 
    setb MY_SCLK    ; Transmit 
    mov c, MY_MISO  ; Read received bit 
    mov a, R1       ; Save received bit in R1 
    rlc a 
    mov R1, a 
    clr MY_SCLK 
    djnz R2, DO_SPI_G_LOOP 
    pop acc 
    ret 

; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
	orl	PCON,#0x80
	mov	SCON,#0x52
	mov	BDRCON,#0x00
	mov	BRL,#BRG_VAL
	mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
    ret

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret
	
Wait1sec:
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	ret
    
Temp:
	db 'Temperature: ', 0

Warning:
	db 'Warning ', 0

Hot:
	db 'HOT', 0
 
MainProgram:
	;Initialize 
    mov SP, #7FH ; Set the stack pointer to the begining of idata
    setb CE_ADC
    lcall INIT_SPI
    lcall InitSerialPort
    lcall LCD_4bit
    
    Set_Cursor(1,1)
    Send_Constant_String(#Temp)

loop:
	clr a
	mov a, mf
	clr a 
	da a
	mov mf, a

	Read_ADC_Channel(0)
	
	lcall hex2bcd
	mov a, R1
	mov result, a
	lcall hex2bcd
	
	;Load_X
	mov x+0, result+0
	mov x+1, result+1
	mov x+2, #0
	mov x+3, #0
	lcall hex2bcd
	
	clr a 
	; Multiply by 410
	load_Y(410)
	lcall mul32
	; Divide result by 1023
	load_Y(1023)
	lcall div32
	; Subtract 273 from result
	load_Y(273)
	lcall sub32
	
	Set_Cursor(1,14)
	Display_BCD(bcd)
	Send_BCD(bcd)
	
	
    mov a , #'\r'
    lcall putChar
    mov a, #'\n'
    lcall putChar
    
    lcall Wait1sec
    ljmp  loop
  
Display_10_digit_BCD:
	Set_Cursor(2,7)
	Display_BCD(bcd+4)  
	Display_BCD(bcd+3) 
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret
END
