; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))
Button_Delay  EQU 100
FREQ1		  EQU 60000
FREQ2		  EQU 58000
SOUND_OUT     equ P1.1

SET_BUTTON 	  equ P2.4
HOURS_BUTTON  equ P4.5
MINUTES_BUTTON equ P0.5
SECONDS_BUTTON equ P0.3
SWAP_BUTTON 	equ P0.1

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
; The BCD counter incrememted in the ISR and displayed in the main loop
Hours: ds 1
Minutes: ds 1
Seconds: ds 1
Ahours: ds 1
Aminutes: ds 1
start: ds 1
Alarm: ds 1
Sound: ds 1
mode: ds 1
counter: ds 1

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

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
	mov RH0, #high(TIMER0_RELOAD)
	mov RL0, #low(TIMER0_RELOAD)
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1.1 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already
	cpl SOUND_OUT
	reti

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
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
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
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	; 1 second have passed.  Set a flag so the main program knows
	setb seconds_flag ; Let the main program know half second had passed
	; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Seconds 
	mov a, Seconds
	cjne a, #0x59, Inc_Seconds ; if secs != 60, go to inc secs
	mov a, #0	;reset the seconds
	da a
	mov Seconds, a
Timer2_minutes:
	mov a, Minutes
	cjne a, #0x59, Inc_Minutes ; if mins != 60, go to inc mins
	mov a, #0 ; reset the mins
	da a
	mov Minutes, a
	;Hours
	mov a, Hours
	jb ap_flag, Noon
	cjne a, #0x11, Inc_hours
	cjne a, #0x12, Afternoon
Afternoon:
	cpl ap_flag
	sjmp Inc_Hours
Noon:
	cjne a, #0x12, Midnight
	mov a, #1
	da a
	mov Hours, a
	sjmp Timer2_ISR_done
Midnight:
	cjne a, #0x11, Inc_Hours
	cpl ap_flag
	mov a, #0
	da a
	mov Hours, a
	sjmp Timer2_ISR_done
Inc_Seconds: ; a alr has the seconds
	add a, #0x01
	da a 
	mov Seconds, a
	sjmp Timer2_ISR_done
Inc_Minutes: ; a alr has the minutes
	add a, #0x01
	da a 
	mov Minutes, a
	sjmp Timer2_ISR_done
Inc_Hours: 
	add a, #0x01
	da a
	mov Hours, a 
	sjmp Timer2_ISR_done
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
line1: db 'Time xx:xx:xxxM', 0
line2: db 'Alarm xx:xxx xxx', 0
Aon: db 'on ', 0
Aoff: db 'off', 0

main:
	; Initialization
    mov SP, #0x7F
    lcall Timer0_Init
    lcall Timer2_Init
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#line1)
    Set_Cursor(2,1)
    Send_Constant_String(#line2)
    clr ap_flag ;ap flag is 0
    clr Aap_flag ; Aap_flag
    mov a, #0x00
    da a 
    mov Alarm, a
    mov Counter, a
    mov Sound, a
    mov start, a
    mov Seconds, a
    mov Minutes, a
    mov Hours, a
    mov mode, a
    mov a, #0x01
    da a
    mov Ahours, a
    mov Aminutes, a
    clr TR0
    ljmp loop

;Alarm
Check_Alarm:
	mov a, Hours
	cjne a, Ahours, Adone ; if != going to Adone
	mov a, Minutes	; if ==
	cjne a, Aminutes, Adone ; if != going to SAlarm
	jb ap_flag, Apm
	jb Aap_flag, Adone
	mov a, mode
	mov a, #0
	da a
	mov mode, a
	mov a, Sound
	jnz Adone
	cpl a
	mov Sound, a
	setb TR0	; make a sound
	sjmp Adone
Apm:
	jnb Aap_flag, Adone
	sjmp Adone
Clear_A:
	mov a, Sound
	jz Adone
	jnb SET_BUTTON, Empty
	ljmp Clear_A
Empty:
	jnb SET_BUTTON, $
	mov a, Sound
	mov a, #0x00
	da a
	mov Sound, a
	clr TR0
	setb TR2
	mov a, mode
	clr a
	mov mode, a
	ljmp Off_A
	
	; After initialization the program stays in this 'forever' loop
loop:
 	clr a
 	mov a, mode
	jnz Check_Alarm
	jz Clear_A
Adone:
	jnb SET_BUTTON, Setup_Set
	mov a, start
	jnz display
	clr TR2
	jnb HOURS_BUTTON, Reset_Hours
	jnb MINUTES_BUTTON, Reset_Minutes
	jnb SECONDS_BUTTON, Reset_Seconds
	ljmp Ext_Alarm
	ljmp display
	;if the set button is not pressed remain in waiting
Setup_Set:
	jnb SET_BUTTON, $
	clr TR0
	cpl TR2
	mov a, Sound
	clr a
	mov Sound, a
	mov a, start
	cpl a
	mov start, a
	mov a, mode
	cpl a
	mov mode, a
Off_A:
	ljmp Start_Alarm
Reset_Seconds:
	jnb SECONDS_BUTTON, $
	mov a, Seconds
	cjne a, #0x59, Up_Seconds ; if secs != 60, go to inc secs
	mov a, #0	;reset the seconds
	da a
	mov Seconds, a
Reset_Minutes:
	jnb MINUTES_BUTTON, $
	mov a, Minutes
	cjne a, #0x59, Up_Minutes ; if mins != 60, go to inc mins
	mov a, #0 ; reset the mins
	da a
	mov Minutes, a
Reset_Hours:
	jnb HOURS_BUTTON, $
	mov a, Hours
	jb ap_flag, ChangePM 
	cjne a, #0x11, Up_Hours
	cjne a, #0x12, Flag_up
Flag_up:
	setb ap_flag
	sjmp Up_Hours
ChangePM:
	cjne a, #0x12, PM12
	mov a, #1
	da a 
	mov Hours, a
	sjmp display
PM12:
	cjne a, #0x11, Up_Hours
	clr ap_flag
	mov a, #0
	da a
	mov Hours, a
	sjmp display
Up_Seconds: ; a alr has the seconds
	add a, #0x01
	da a 
	mov Seconds, a
	sjmp display
Up_Minutes: ; a alr has the minutes
	add a, #0x01
	da a 
	mov Minutes, a
	sjmp display
display:
    clr seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
	Set_Cursor(1, 12)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(Seconds) ; This macro is also in 'LCD_4bit.inc'
    Set_Cursor(1, 9)
    Display_BCD(Minutes)
    Set_Cursor(1, 6)
    Display_BCD(Hours)
    jb ap_flag, Set_PM
    Set_Cursor(1, 14)
    Display_char(#'A')
    ljmp loop
Up_Hours: 
	add a, #0x01
	da a
	mov Hours, a 
	sjmp display
Ext_Alarm:
	jnb SWAP_BUTTON, Reset_Alarm
	ljmp loop
Set_PM:
	Set_Cursor(1, 14)
	Display_char(#'P')
    ljmp loop
Start_Alarm:
	clr a
	mov a, Alarm
	cpl a
	jnz On_A
	Set_Cursor(2,14)
	Send_Constant_String(#Aoff)
	mov Alarm, a
	ljmp loop
On_A:
	Set_Cursor(2, 14)
	Send_Constant_String(#Aon)
	mov Alarm, a
	ljmp loop
Inc_Aminutes:
	add a, #0x01
	da a 
	mov Aminutes, a
	ljmp display_A
Reset_Alarm:
	jnb SWAP_BUTTON, $
	mov a, Aminutes
	cjne a, #0x59, Inc_Aminutes
	mov a, #0
	da a
	mov Aminutes, a
Reset_Ahours:
	mov a, Ahours
	cjne a, #0x11, Inc_Ahours
	add a, #0x01
	da a
	mov Ahours, a
	ljmp display_A
Inc_Ahours:
	add a, #0x01
	da a
	mov Ahours, a
	ljmp display_A
display_A:
	Set_Cursor(2,7)
	Display_BCD(Ahours)
	Set_Cursor(2,10)
	Display_BCD(Aminutes)
	jb Aap_flag, SetAPM
	Set_Cursor(2,12)
	Display_char(#'A')
	Set_Cursor(2,14)
	Send_Constant_String(#Aoff)
	ljmp loop
SetAPM:
	Set_Cursor(2,12)
	Display_char(#'P')
	ljmp loop
END
