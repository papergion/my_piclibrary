; ---------------------------------------------------------------------------------
;       File: canrepro_232_boot.ASM
; ---------------------------------------------------------------------------------
; aggiornamento firmware pic18f26k80 - input da UART (1 o 2)
; va allocato in pic18f26k80 da 0x0000 a 0x01FF 
; entra in azione al boot - attende e memorizza messaggio iniziale ESP01 (75188 baud)
;    poi attende comando 0x11 (riprogramma) oppure 0xF0 (start)
;       in assenza di comandi va in timeout dopo 64 secondi e va in start (0x400)
; il pgm di aggiornamento firmware CANREPRO_232_EVO_BOOT va allocato a 0x0200-0x03FF
; il main va allocato da 0x400 e deve rimappare i vettori di interrupt a 0x408 e 0x418
;    ( usare 18F26K80_BOOT.LKR )
; va compilato con versione modificata di c018i.C
; ---------------------------------------------------------------------------------

#ifndef _P18CXXX_H
#define _P18CXXX_H
         INCLUDE <p18CXXX.INC>
#endif

; ---------------------------------------------------------------------------------
 INCLUDE <canrepro.inc>
; ---------------------------------------------------------------------------------

#ifndef _USE_UART1 
#ifndef _USE_UART2 
	#define _USE_UART2  ; default UART2
#endif
#endif

        RADIX DEC
        global    RVReset
        extern    REPROmainB
		global    bootMsg
; ---------------------------------------------------------------------------------
reproboot    udata
; ---------------------------------------------------------------------------------
timCtr       res 2;
bootMsg      res 160
cush         res 1;



; *****************************************************************************
	ORG	0x0000			; Re-map Reset vector
	bra	Setup	
	bra	Setup

	ORG	0x0008
VIntH
	bra	RVIntH			; Re-map Interrupt vector

	ORG	0x0018
VIntL
	bra	RVIntL			; Re-map Interrupt vector
; *****************************************************************************

; esp01-> 75188baud - 38mS - msg1 - 16mS - msg2 - 

; *****************************************************************************
; Setup the appropriate registers.
Setup
    clrf	OSCTUNE
    movlw   b'01110000' ;           // 16Mhz x 4 = 64Mhz - obbligatorio 16 or 64
    movwf   OSCCON		;           // 16Mhz x 4 = 64Mhz - obbligatorio 16 or 64
    clrf	OSCTUNE
    bsf     OSCTUNE,PLLEN ;         // x4

    btfss   OSCCON,HFIOFS ;			// wait for frequency stable
     bra    $ -2

; *****************************************************************************
    bcf     TRIS_LED
    bcf     BUS_OUT
    movlw	b'00110010'     ;
    movwf   T3CON
    bsf     T3CON,TMR3ON    ; timer start
	bcf     PIR2, TMR3IF    ; 32mS
    movlb   HIGH(timCtr)    ; PER INDIRIZZARE DATA BANK
    clrf    timCtr
    clrf    timCtr+1
; *****************************************************************************

; aspetta sino a che il pin RX rimane costantemente alto per 32mS

	bcf		TRISC, 6		; Setup tx pin
	bsf		TRISC, 7		; Setup rx pin UART1

WaitInit
    clrf    TMR3H
    clrf    TMR3L
WaitFirst
    clrwdt
    btfss   PORTC,7     ; Test rx pin UART1
      bra   WaitInit
	btfss   PIR2, TMR3IF
     bra    WaitFirst
	bcf     PIR2, TMR3IF

; prima connessione a 75188 baud per leggere lo stream iniziale di esp8266

    bsf     RCSTA1,SPEN
    movlw   b'00001000'     ; // 16 bit baud gen
    movwf   BAUDCON1

    movlw   0				; 115200 baud
    movwf   SPBRGH1
    movlw   211				; 75188 baud
    movwf   SPBRG1

	movlw	b'10010000'		; Setup rx 
	movwf	RCSTA1
	movlw	b'00100110'		; Setup tx high-speed
	movwf	TXSTA1
    bcf     PIR1,RC1IF

; *****************************************************************************

    bsf     SYS_LED			; led acceso: in wait

; *****************************************************************************

    lfsr    0,bootMsg		; pointer at start of buffers

;	movlw   '>'
;	movwf   POSTINC0
	
	btfsc	RCSTA1, OERR	; Reset on overun
	 bra	WaitData    

	bcf		RCSTA1,CREN;
	nop
	bsf		RCSTA1,CREN;

WaitData
	btfss	PIR1, RC1IF		; Wait for data from RS232
	 bra	NoByte
	movff	RCREG1,POSTINC0    ;// update buffer contents
NoByte
	btfss   PIR2, TMR3IF
     bra    WaitData
	bcf     PIR2, TMR3IF
    incf    timCtr
    btfss   timCtr,2
     bra    WaitData

    clrf    INDF0         ; end of buffer
	clrf	cush;

; riconnessione a 115200 baud 

    movlw   137				; 115200 baud
    movwf   SPBRG1

; *****************************************************************************
; Read and parse the data.
StartOfLine
	rcall	RdRS232			; Get byte
	
    xorlw   0xF0
    bz      GoAhead           
    xorlw   0xF0 ^ 0x11
	bz      GoRepro
	bra 	StartOfLine		; Yes, start over	

GoRepro
    goto	REPROmainB

GoAhead
	bra		RVReset



; *****************************************************************************
RdRS232
	clrwdt
	btfsc	RCSTA1, OERR	; Reset on overun
	 bra	RdLoop    

	bcf		RCSTA1,CREN;
	nop
	bsf		RCSTA1,CREN;

RdLoop
    clrwdt
	btfsc   PIR2, TMR3IF
     bra    RdTimer
     
	btfss	PIR1, RC1IF		; Wait for data from RS232
	 bra	RdLoop	
	movf	RCREG1, W		; Save the data

    bcf     SYS_LED			; led spento - ricevuto
 	return

RdTimer
	bcf     PIR2, TMR3IF    ; 32mS
    bcf     SYS_LED			; spegne led

    btfsc   timCtr,1        ; 32mS x 4 = 128mS
     bsf    SYS_LED			; accende il led

    incfsz  timCtr
	 bra	RdLoop	
	 
	incf    timCtr+1        ; x 256 = 8sec
    btfss   timCtr+1,2
	 bra	RdLoop	
	                        ; x 8 = 64sec - timeout
; timeout
    bcf     SYS_LED			; led spento - timeout
    movlw   0xF0
    return
; *****************************************************************************






	ORG	0x400
RVReset					

	ORG	0x408
RVIntH

	ORG	0x418
RVIntL

        end