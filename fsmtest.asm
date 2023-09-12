$MODLP51RC2
org 0000H
   ljmp MainProgram

org 0x002B
   ljmp Timer2_ISR

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
TIMER2_RATE   EQU 1000    
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOAK_TEMP  EQU 160
REFLOW_TEMP EQU 210
COOLING_TEMP EQU 50

DSEG at 0x30
	result: ds 4
	bcd: ds 5
	x: ds 4
	y: ds 4
	temp_soak: ds 1
	time_soak: ds 1
	temp_reflow: ds 1 
	time_reflow: ds 1 
	state: ds 1
	temp: ds 1
	time: ds 1
	sec: ds 1
	Count1ms: ds 2
	pwm: ds 1
	pwm_ratio: ds 2
	mode: ds 1
	BCD_counter: ds 1
	time_display: ds 1

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
SOAKTIME_BUTTON equ P4.5
SOAKTEMP_BUTTON equ P0.5
REFLOWTIME_BUTTON	equ P0.3
REFLOWTEMP_BUTTON equ P0.1

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
	cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Do the PWM thing
	; Check if Count1ms > pwm_ratio (this is a 16-bit compare)
	clr c
	mov a, pwm_ratio+0
	subb a, Count1ms+0
	mov a, pwm_ratio+1
	subb a, Count1ms+1
	; if Count1ms > pwm_ratio  the carry is set.  Just copy the carry to the pwm output pin:
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
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

read_temp:
	Read_ADC_Channel(0)
	lcall hex2bcd
	mov a, R1
	mov result, a
	ret

;--------------;
; fsm machine  ;  the oven turn on/off in the fsm
;--------------; 
fsm_machine:
	mov a, state
state0:
	cjne a, #0, state1	;if != 0 jmp to 1
	Set_Cursor(1,1)
	Send_Constant_String(#stage0)
	mov pwm, #0	;stop the oven (power = 0)
	lcall LCD_Menu	;jump to Menu and allow user to configure time, temp at each state
	
state1:	;ramp to soak
	cjne a, #1, state2
	setb TR2  ; Enable timer 2
	Set_Cursor(1,1)
	Send_Constant_String(#stage1)
	mov pwm, #1	;turn on the oven
	mov a, temp
	cjne a, #SOAK_TEMP, loop ; if current temp != 160, jump to loop
	;if temp == soak temp, mov to next state
	mov a, state	;inc state
	inc a 
	mov state, a 
	lcall LCD_Process ;jump to LCD process when oven is on
	
state2: ;soak period
	cjne a, #2, state3
	Set_Cursor(1,1)
	Send_Constant_String(#stage2)
	mov a, time_soak
	dec a 
	mov a, time
	cjne a, time_soak, LCD_Process	;if time_soak != 0, jump to display LCD Process
	;if time_soak == 0
	mov a, state	;inc state
	add a, #0x01
	da a 
	mov state, a
	lcall LCD_Process
	
state3:	;ramp to peak
	cjne a, #3, state4
	mov pwm, #1 ;turn on the oven
	Set_Cursor(1,1)
	Send_Constant_String(#stage3)
	mov a, temp
	cjne a, #REFLOW_TEMP, loop ; if current temp != reflow temp, go to loop
	;if current temp == reflow temp, mov to next state
	mov a, state	;inc state
	inc a 
	mov state, a
	lcall LCD_Process
	
state4:	;reflow period
	cjne a, #4, state5
	Set_Cursor(1,1)
	Send_Constant_String(#stage4)
	mov a, time_reflow
	dec a 
	cjne a, time_reflow, loop	;if time_soak != 0, jump to loop
	;if time_soak == 0
	mov a, state	;inc state
	add a, #0x01
	da a
	mov state, a
	lcall LCD_Process
	
state5: ;cooling
	cjne a, #5, forever
	mov pwm, #0	; turn off the oven
	Set_Cursor(1,1)
	Send_Constant_String(#stage5)
	lcall Done_sound
	lcall forever	

LCD_Process: ;when the oven is on 
	lcall loop

;-------------;
; Start Here  ;
;-------------;

stage0:
	db 'Stage 0', 0
stage1:
	db 'Stage 1', 0
stage2:
	db 'Stage 2', 0
stage3:
	db 'Stage 3', 0
stage4:
	db 'Stage 4', 0
stage5:
	db 'Stage 5', 0

MainProgram:
	;Initialize 
    mov SP, #7FH ; Set the stack pointer to the begining of idata
    setb CE_ADC
    lcall INIT_SPI
    lcall InitSerialPort
    lcall Timer2_Init
    lcall LCD_4bit 
    mov a, #0x00 ;Set all the variables to 0
    da a 			
    mov state, a ;state after reset is state 0 (waiting state)
    mov mode, a
    mov time_soak, a
	mov temp_soak, a
	mov time_reflow, a
	mov temp_reflow, a
	lcall forever
    
forever:	; Check for buttons inputs
	clr a 
	clr TR2
	jnb SOAKTIME_BUTTON, Inc_soaktime
	jnb SOAKTEMP_BUTTON, Inc_soaktemp
	jnb REFLOWTIME_BUTTON, Inc_reflowtime
	jnb REFLOWTEMP_BUTTON, Inc_reflowtemp
loop:	;when the ovenis on, only consider button start	
	jnb START_BUTTON, start	
	lcall read_temp	;update the temp variable
	lcall fsm_machine	;LCD will be call in the fsm	
    ljmp  forever
	
LCD_Menu:	
	lcall forever	

done_sound:
	lcall forever
	
start:	; when the start is pressed 
	jnb START_BUTTON, $	;wait for the button to release
	mov a, mode 
	cjne a, #0x00, stopfunc	;jmp if != 0
	cpl a ;set the start button to become a stop button
	mov mode, a
	mov a, state
	mov a, #0x01
	mov state, a	;configure to state 1
	lcall loop	;jump back to loop

stopfunc:	;when the oven is working and the start is pressed
	mov a, mode
	cpl a ; configure the mode again so this button become a start button
	mov mode, a
	mov a, state ;set the state to be state0
	mov a, #0x00
	da a
	mov state, a
	lcall loop
    
Reset_soaktime:	;The soak time button is pressed
	jnb SOAKTIME_BUTTON, $
	mov a, time_soak
	cjne a, #0x59, Inc_soaktime ;if time is not bigger than 60, inc it
	mov a, #0
	da a
	mov time_soak, a
	lcall LCD_Menu
Inc_soaktime:	
	add a, #0x01
	da a
	mov a, time_soak
	lcall LCD_Menu

Reset_soaktemp: ;the soak temp button is pressed
	jnb SOAKTEMP_BUTTON, $
	mov a, temp_soak
	add a, #0x01
	da a
	mov temp_soak, a
	lcall LCD_Menu

Inc_reflowtemp: ; the reflow temp is pressed
	jnb REFLOWTEMP_BUTTON, $
	mov a, temp_reflow
	add a, #0x01
	da a
	mov temp_reflow, a
	lcall LCD_Menu

Inc_reflowtime: ;the reflow time is pressed
	jnb REFLOWTIME_BUTTON, $
	mov a, time_reflow
	add a, #0x01
	da a
	mov time_reflow, a
	lcall LCD_Menu
END
