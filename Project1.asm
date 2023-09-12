$MODLP51RC2
org 0000H
   ljmp MainProgram

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

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
	temp_soak: ds 1
	time_soak: ds 1
	temp_refl: ds 1 
	time_refl: ds 1 
	state: ds 1
	temp: ds 1
	time: ds 1
	sec: ds 1
	pwm_ratio: ds 2
	Count1ms: ds 2
	mode: ds 1
	cold: ds 1
	
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

START_BUTTON equ P2.4
SHIFT_PB equ P2.6
SOAKTIME_BUTTON equ P0.5
SOAKTEMP_BUTTON equ P4.5
REFLTIME_BUTTON	equ P0.1
REFLTEMP_BUTTON equ P0.3

PWM_OUTPUT equ P1.0

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
	push IE ; Save the current state of bit EA in the stack
	clr EA ;Disable interrupts
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
	pop IE
ret

;------------------------;
;  Set up default values ;
;------------------------;

Load_Defaults:	
	mov temp_soak, #150
	mov time_soak, #45
	mov temp_refl, #225
	mov time_refl, #30
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

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
	setb TR2
    setb ET2  ; Enable timer 2 interrupt
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR

	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	;Do the PWM thing
	clr c
	mov a, pwm_ratio+0
	subb a, Count1ms+0
	mov a, pwm_ratio+1
	subb a, Count1ms+1
	mov PWM_OUTPUT, c
	
	; Check if a second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Increment binary variable 'seconds'
	inc sec
	inc time
	lcall Read_temp
Timer2_ISR_done:
	pop psw
	pop acc
	reti

Read_temp:
	clr a
	Read_ADC_Channel(0)
	;Load_X
	mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0	
	; Multiply by 410
	load_Y(410)
	lcall mul32
	; Divide result by 1023
	load_Y(1023)
	lcall div32
	; Subtract 273 from result
	load_Y(273)
	lcall sub32
	mov cold, x+0
	
	;Thermocouple
	Read_ADC_Channel(1)
	;Load_X
	mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0
	Load_Y(283)
	lcall mul32
	Load_Y(1000)
	lcall div32
	
	;put the cold temp into Y
	mov y+0, cold+0
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	lcall add32
	; the addtion will be in x
	
	lcall hex2bcd
	mov temp+1, bcd+1
	mov temp, bcd
	Send_BCD(bcd+1)
	Send_BCD(bcd+0)
	;the final temp
	
    mov a , #'\r'
    lcall putChar
    mov a, #'\n'
    lcall putChar
ret

;-------------;
; Start Here  ;
;-------------;
LCD_Menu:
	 db 'TS  tS  TR  tR  ', 0
	 
Clear_board:
	db '                 ', 0

Stage1:
	db 'Stage1           ', 0

Stage2:
	db 'Stage2           ', 0

Stage3:
	db 'Stage3           ', 0
	
Stage4:
	db 'Stage4           ', 0
	
Stage5:
	db 'Stage5           ', 0

Temp_dis:
	db 'Time:   Temp     ', 0

MainProgram:
	;Initialize 
    mov SP, #7FH ; Set the stack pointer to the begining of idata
    mov P0M0, #0
    mov P0M1, #0
    setb CE_ADC
    setb EA
    lcall INIT_SPI
    lcall InitSerialPort
    lcall Timer2_Init
    lcall LCD_4bit 
    lcall Load_Configuration
    
forever: 
	mov a, #0 ;Set all the variables to 0			
    mov state, a ;state after reset is state 0 (waiting state)
    mov sec, a
    mov time, a
    mov mode, a
    Set_Cursor(1,1)
    Send_Constant_String(#LCD_Menu)
    Set_Cursor(2,1)
    Send_Constant_String(#Clear_board)
    
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
 	; After initialized 
loop:
	clr TR2	;stop the clk 
	Change_8bit_Variable(SOAKTEMP_BUTTON, temp_soak, loop_a)
	Set_Cursor(2, 1)
	mov a, temp_soak
	lcall SendToLCD
	lcall Save_Configuration 
loop_a:   
    Change_8bit_Variable(SOAKTIME_BUTTON, time_soak, loop_b)
	Set_Cursor(2, 5)
	mov a, time_soak
	lcall SendToLCD
	lcall Save_Configuration 
loop_b:   
    Change_8bit_Variable(REFLTEMP_BUTTON, temp_refl, loop_c)
	Set_Cursor(2, 9)
	mov a, temp_refl
	lcall SendToLCD
	lcall Save_Configuration
loop_c:   
    Change_8bit_Variable(REFLTIME_BUTTON, time_refl, loop_d)
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration
loop_d:
	clr a 
	jnb START_BUTTON, start
	ljmp fsm_machine	;update the temp variable
	
start:	; when the start is pressed 
	jnb START_BUTTON, $	;wait for the button to release
	setb TR2
	mov a, mode 
	cjne a, #0, stopfunc	;jmp if != 0
	cpl a ;set the start button to become a stop button
	mov mode, a
	mov a, state
	add a, #1
	da a
	mov state, a	;configure to state 1
	ljmp loop_d
stopfunc:	;when the oven is working and the start is pressed
	clr TR2
	mov a, mode
	clr a 
	mov mode, a
	clr PWM_OUTPUT
	mov a, state
	mov a, #0
	da a
	mov state, a
	ljmp forever
;--------------;
; fsm machine  ;  the oven turn on/off in the fsm
;--------------; 
fsm_machine:
	mov a, state
state0:
	cjne a, #0, state1	;if != 0 jmp to state 1
	mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
	clr PWM_OUTPUT
	ljmp loop	;jump to Menu and allow user to configure time, temp at each state
state1:	;ramp to soak
	cjne a, #1, state2
	setb PWM_OUTPUT
	mov a, #41
	clr c
	subb a, sec
	jnc LCD_Stage1 ; if temp < temp_soak, go to LCD_Stage1-Process
	;if temp > soak temp, mov to next state
	mov a, state	;inc state
	add a, #1
	da a
	mov state, a 
	mov a, time		;reset up a timer 
	mov a, #0
	mov time, a	
LCD_Stage1:
	Set_Cursor(1,1)
	Send_Constant_String(#Stage1)
	ljmp LCD_Process
state2: ;soak period
	cjne a, #2, state3
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(200)
	mov a, #86
	clr c		
	subb a, sec	; compare with time_soak
	jnc LCD_Stage2	;if time_soak > timer, jump to display LCD_Stage2/Process
	;if time_soak < timer
	mov a, state	;inc state
	add a, #1
	da a 
	mov state, a	
LCD_Stage2:
	Set_Cursor(1,1)
	Send_Constant_String(#Stage2)
	ljmp LCD_Process
state3:	;ramp to peak
	cjne a, #3, state4
	mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
	setb PWM_OUTPUT
	mov a, #123
	clr c
	subb a, sec
	jnc LCD_Stage3 ; if temp < temp_refl, go to LCD_Stage1-Process
	;if temp > temp_reflo, mov to next state
	mov a, state	;inc state
	add a, #1
	da a
	mov state, a
	mov a, time		;reset up a timer 
	mov a, #0
	da a
	mov time, a
LCD_Stage3:
	Set_Cursor(1,1)
	Send_Constant_String(#Stage3)
	ljmp LCD_Process	
state4:	;reflow period
	cjne a, #4, state5
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(200)
	mov a, #153
	clr c
	subb a, sec
	jnc LCD_Stage4	;if time_refl > timer, jump to display LCD_Stage2/Process
	;if time_refl < timer
	mov a, state	;inc state
	add a, #1
	da a
	mov state, a
LCD_Stage4:
	Set_Cursor(1,1)
	Send_Constant_String(#Stage4)
	ljmp LCD_Process	
state5: ;cooling period
	mov pwm_ratio+0, #low(1000)
	mov pwm_ratio+1, #high(1000)
	clr PWM_OUTPUT
	Set_Cursor(1,1)
	Send_Constant_String(#Stage5)
	mov a, #182
	clr c		
	subb a, sec					;Edit when thermometer is ready
	jnc LCD_Process ;if 60 C < temp, Wait
	ljmp forever ; basically reset
LCD_Process: ;when the oven is on 
	Set_Cursor(2,1)
	Send_Constant_String(#Temp_dis)
	Set_Cursor(2,6)
	mov a, sec
	lcall SendToLCD
	Set_Cursor(2,13)
	Display_BCD(temp+1)
	Display_BCD(temp)
    ljmp  loop_d
END
