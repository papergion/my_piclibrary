; ---------------------------------------------------------------------------------
;       File: canrepro_232_boot.asm
; ---------------------------------------------------------------------------------
; boot firmware pic18f26k80 - input da UART (1 o 2)
; va allocato in pic18f26k80 da 0x0000 a 0x01FF 
; entra in azione al boot e attende comando 0x11 (riprogramma) oppure 0xF0 (start)
;       in assenza di comandi va in timeout dopo 64 secondi e va in start (0x400)
; il pgm di aggiornamento firmware CANREPRO_232_EVO_BASE va allocato a 0x0200-0x03FF
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

; ---------------------------------------------------------------------------------
reproram     udata
; ---------------------------------------------------------------------------------
timCtr       res 2;
 
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

#ifdef _USE_UART1 
	bcf	TRISC, 6		; Setup tx pin
	bsf	TRISC, 7		; Setup rx pin

    bsf     RCSTA1,SPEN
    movlw   b'00001000'     ; // 16 bit baud gen
    movwf   BAUDCON1

    movlw   0				; 115200 baud
    movwf   SPBRGH1
    movlw   137
    movwf   SPBRG1

	movlw	b'10010000'		; Setup rx 
	movwf	RCSTA1
	movlw	b'00100110'		; Setup tx high-speed
	movwf	TXSTA1
    bcf     PIR1,RC1IF
#endif

#ifdef _USE_UART2 
	bcf	TRISB, 6		; Setup tx pin
	bsf	TRISB, 7		; Setup rx pin
    
    bsf     RCSTA2,SPEN
    movlw   b'00001000'     ; // 16 bit baud gen
    movwf   BAUDCON2

    movlw   0				; 115200 baud
    movwf   SPBRGH2
    movlw   137
    movwf   SPBRG2

	movlw	b'10010000'		; Setup rx 
	movwf	RCSTA2
	movlw	b'00100110'		; Setup tx high-speed
	movwf	TXSTA2
    bcf     PIR3,RC2IF
#endif
; *****************************************************************************
    bcf     TRIS_LED
    bcf     BUS_OUT
    movlw	b'00110010'     ;
    movwf   T3CON
    bsf     T3CON,TMR3ON    ; timer start
	bcf     PIR2, TMR3IF    ; 32mS
    movlb   HIGH(timCtr)    ;// PER INDIRIZZARE DATA BANK
    clrf    timCtr
    clrf    timCtr+1
; *****************************************************************************

    bsf     SYS_LED			; led acceso: in wait

; *****************************************************************************
; Wait 128mS
WaitLoop
    clrwdt
	btfss   PIR2, TMR3IF
     bra    WaitLoop
	bcf     PIR2, TMR3IF    ; 32mS
    incf    timCtr
    btfss   timCtr,2
     bra    WaitLoop

; *****************************************************************************
; Read and parse the data.
StartOfLine
	rcall	RdRS232			; Get byte
	
    xorlw   0xF0
    bz      GoAhead           
;    xorlw   0xF1 ^ 0xF2
;    bz      GoAhead           
;    xorlw   0xF2 ^ 0x11
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

#ifdef _USE_UART1 
	btfsc	RCSTA1, OERR	; Reset on overun
#endif
#ifdef _USE_UART2 
	btfsc	RCSTA2, OERR	; Reset on overun
#endif
	reset

RdLoop
    clrwdt
	btfsc   PIR2, TMR3IF
     bra    RdTimer
     
#ifdef _USE_UART1 
	btfss	PIR1, RC1IF		; Wait for data from RS232
	 bra	RdLoop	
	movf	RCREG1, W		; Save the data
#endif
#ifdef _USE_UART2 
	btfss	PIR3, RC2IF		; Wait for data from RS232
	 bra	RdLoop	
	movf	RCREG2, W		; Save the data
#endif
	
    bcf     SYS_LED			; led spento - ricevuto
;	movwf	RXDATA
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