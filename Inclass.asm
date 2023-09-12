$NOLIST
$MODLP51RC2
$LIST

; Reset vector
org 0x0000
    ljmp main

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
temp_soak: ds 1 
time_soak: ds 1
temp_refl: ds 1
time_refl: ds 1

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
seconds_flag: dbit 1 ; Set to one in the ISR every time 1s had passed
ap_flag: dbit 1
Aap_flag:	dbit 1

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

CE_ADC    EQU  P2.0 
MY_MOSI   EQU  P2.1  
MY_MISO   EQU  P2.2 
MY_SCLK   EQU  P2.3 

SHIFT_PB	  equ P2.4
TEMP_SOAK_PB  equ P4.5
TIME_SOAK_PB  equ P0.5
TEMP_REFL_PB  equ P0.3
TIME_REFL_PB  equ P0.1

$NOLIST
$include(LCD_4bit.inc)
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

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

SendToLCD:
	mov b, #100
	div ab
	orl a, #0x30 ; Convert hundreds to ASCII
	lcall ?WriteData ; Send to LCD
	mov a, b    ; Remainder is in register b
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall ?WriteData; Send to LCD
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall ?WriteData; Send to LCD
ret
	
Load_Configuration:
	mov dptr, #0x7f84 ; First key value location.
	getbyte(R0) ; 0x7f84 should contain 0x55
	cjne R0, #0x55, Load_Defaults
	getbyte(R0) ; 0x7f85 should contain 0xAA
	cjne R0, #0xAA, Load_Defaults
	; Keys are good.  Get stored values.
	mov dptr, #0x7f80
	getbyte(temp_soak) ; 0x7f80
	getbyte(time_soak) ; 0x7f81
	getbyte(temp_refl) ; 0x7f82
	getbyte(time_refl) ; 0x7f83
ret

Save_Configuration:
	mov FCON, #0x08 ; Page Buffer Mapping Enabled (FPS = 1)
	mov dptr, #0x7f80 ; Last page of flash memory
	; Save variables
	loadbyte(temp_soak) ; @0x7f80
	loadbyte(time_soak) ; @0x7f81
	loadbyte(temp_refl) ; @0x7f82
	loadbyte(time_refl) ; @0x7f83
	loadbyte(#0x55) ; First key value @0x7f84
	loadbyte(#0xAA) ; Second key value @0x7f85
	mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
	orl EECON, #0b01000000 ; Enable auto-erase on next write sequence
	mov FCON, #0x50 ; Write trigger first byte
	mov FCON, #0xA0 ; Write trigger second byte
	; CPU idles until writing of flash completes.
	mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
	anl EECON, #0b10111111 ; Disable auto-erase
ret

Load_Defaults:
	mov temp_soak, #150
	mov time_soak, #45
	mov temp_refl, #225
	mov time_refl, #30
ret

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
Initial_Message: db 'TS  tS  TR  tR', 0

main:
	; Initialization
    mov SP, #7FH
    mov P0M0, #0
    mov P0M1, #0
    
    lcall LCD_4BIT
 	lcall Load_Configuration
 	   
    Set_Cursor(1,1)
    Send_Constant_String(#Initial_Message)
    
    ;Display the variables
    Set_Cursor(2,1)
    mov a, temp_soak
    lcall SendToLCD
    
    Set_Cursor(2,5)
    mov a, time_soak
    lcall SendToLCD
 
    Set_Cursor(2,9)
    mov a, temp_refl
    lcall SendToLCD
 
    Set_Cursor(2,13)
    mov a, time_refl
    lcall SendToLCD
    
loop:
	Change_8bit_Variable(TEMP_SOAK_PB, temp_soak, loop_a)
	Set_Cursor(2, 1)
	mov a, temp_soak
	lcall SendToLCD
	lcall Save_Configuration 
loop_a:   
    Change_8bit_Variable(TIME_SOAK_PB, time_soak, loop_b)
	Set_Cursor(2, 5)
	mov a, time_soak
	lcall SendToLCD
	lcall Save_Configuration 
loop_b:   
    Change_8bit_Variable(TEMP_REFL_PB, temp_refl, loop_c)
	Set_Cursor(2, 9)
	mov a, temp_refl
	lcall SendToLCD
	lcall Save_Configuration
loop_c:   
    Change_8bit_Variable(TIME_REFL_PB, time_refl, loop_d)
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration
loop_d:

;put fsm here
;if needed put fsm2 
;code to measure temp
Cold_junc:
Hot_junc:

	ljmp loop
END
