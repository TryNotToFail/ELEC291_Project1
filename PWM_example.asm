; This program shows how to do a pwm with a period of 1 s.
; 
; It uses the ISR for timer 2.
;
; The main loop will set the pwm output as follows:
; 20% for 15 seconds 
; 100% for 15 seconds
; 50% for 15 seconds
; 0% for 15 seconds
;
; The output is in P1.0.  You should be able to see the pwm change if you attach an LED with
; a resistor to P1.0 (pin 1 of the microcontroller) as you did with the blinky example
; of lab #1.
;
$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

PWM_OUTPUT    equ P1.0 ; Attach an LED (with 1k resistor in series) to P1.0

; Reset vector
org 0x0000
    ljmp main

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

dseg at 0x30
Count1ms:     ds 2
pwm_ratio:    ds 2
seconds:      ds 1

cseg

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
	inc seconds
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

main:
	; Initialization
    mov SP, #0x7F
    lcall Timer2_Init
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ; Enable Global interrupts
    
    ; Set the default pwm output ratio to 20%.  That is 200ms of every second:
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(200)
	
	; Initialize the seconds counter to zero
	mov seconds, #0
	
	; After initialization the program stays in this 'forever' loop
loop:
	mov a, seconds
	cjne a, #15, loop_a
	; For testing: after 15 seconds change the pwm to 100%:
	mov pwm_ratio+0, #low(1000)
	mov pwm_ratio+1, #high(1000)
	ljmp loop
loop_a:
	cjne a, #30, loop_b
	; For testing: after 30 seconds change the pwm to 50%:
	mov pwm_ratio+0, #low(500)
	mov pwm_ratio+1, #high(500)
	ljmp loop
loop_b:
	cjne a, #45, loop_c
	; For testing: after 45 seconds change the pwm back to 0% :
	mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
	ljmp loop
loop_c:
	cjne a, #60, loop
	; For testing: after 60 seconds change the pwm back to 20% and repeat:
	mov seconds, #0
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(200)
    ljmp loop
END