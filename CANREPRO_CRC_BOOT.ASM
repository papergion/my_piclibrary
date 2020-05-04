; ---------------------------------------------------------------------------------
;       File: canrepro_crc_boot.asm
; ---------------------------------------------------------------------------------
;
; aggiornamento firmware pic18f26k80 - input da messaggi CAN - versione con controllo
;   di checksum piu robusto - mini crc
;
; va allocato in pic18f26k80 da 0x0000 a 0x3FFF - programma da 0400 a EFFF
; entra in azione al boot
;    attende comando 0x11 (riprogramma) oppure 0xF0 (start)
;    in assenza di comandi va in timeout dopo 64 secondi e va in start (0x400)
; il main va allocato a 0x400 e deve rimappare i vettori di interrupt a 0x408 e 0x418
;    ( usare 18F26K80_BOOT.LKR )
; va compilato con versione modificata di c018i.C
; ---------------------------------------------------------------------------------

#ifndef _P18CXXX_H
#define _P18CXXX_H
         INCLUDE <p18CXXX.INC>
#endif

#define ECAN_CONFIG_MODE                0x80
#define ECAN_NORMAL_MODE                0x00

; ---------------------------------------------------------------------------------
#include "canrepro.inc"
; ---------------------------------------------------------------------------------
        RADIX DEC

        global    RVReset
        global    REPROmainB
 IFDEF REPRO_DEBUG
        global    REPRO_TestReceiveMessages
        global    RxMessage
        global    RxRC

        global    HostAddress
        global    MyAddress
 ENDIF

; ---------------------------------------------------------------------------------
reproram     udata
; ---------------------------------------------------------------------------------
RxRC             res 1;
RxMessage        res 13;
TxMessage        res 13;
HostAddress      res 1;
MyAddress        res 1;
LastTXBufferUsed res 1;
TXHead           res 1;
FlashLength      res 1;
FlashAddress     res 2;
CheckWord        res 2;
CanCommand       res 1;  //x00: query version  (received from main proc!)
                      ;  //x01: new flash block binary mode - AA: address - L: data length (8-16-24-32-40-48-56-64)
                      ;  //x02: end flash block binary mode - CCKK: check-word (sum of values)
                      ;  //x03: end flash block binary mode - NO WRITE
                      ;  //x40:
                      ;  //x80: end repro - reboot
iTimeout         res 3;
FlashData        res 64;
FlashPtr         res 1;
ReproError       res 1;
i                res 1;
temp             res 1;

crcdep			 res 1; deposito CRC
crcseq			 res 1; sequenza CRC
crcnumr			 res 1;   contatore numero di shift

timCtr			 res 2;

 IFDEF REPRO_DEBUG
saveFSR0H        res 1;
saveFSR0L        res 1;
saveFSR1H        res 1;
saveFSR1L        res 1;
saveFSR2H        res 1;
saveFSR2L        res 1;
iDebug           res 1;
 ENDIF
;--------------------------------------------------------------------------------------
REPRO_VERSION         EQU  0x0C
CMD_FIRMWARE          EQU  0x07
ECAN_SET_FIFO_MODE    EQU  0xA0
ECAN_SELECT_RX_BUFFER EQU  0x10
MAPPED_CON            EQU  RXB0CON
MAPPED_SIDH           EQU  RXB0SIDH
MAPPED_TXREQ          EQU  FILHIT3
;--------------------------------------------------------------------------------------
#DEFINE RX_PDUFORMAT_TOP      RxMessage
#DEFINE RX_PDUFORMAT          RxMessage+1
#DEFINE RX_PDUSPECIFIC        RxMessage+2
#DEFINE RX_SOURCEADDRESS      RxMessage+3
#DEFINE RX_LENGTH             RxMessage+4
#DEFINE RX_DATA0              RxMessage+5
#DEFINE RX_DATA1              RxMessage+6
#DEFINE RX_DATA2              RxMessage+7
;--------------------------------------------------------------------------------------
#DEFINE TX_PDUFORMAT_TOP      TxMessage
#DEFINE TX_PDUFORMAT          TxMessage+1
#DEFINE TX_PDUSPECIFIC        TxMessage+2
#DEFINE TX_SOURCEADDRESS      TxMessage+3
#DEFINE TX_LENGTH             TxMessage+4
#DEFINE TX_DATA0              TxMessage+5
#DEFINE TX_DATA1              TxMessage+6
#DEFINE TX_DATA2              TxMessage+7
#DEFINE TX_DATA3              TxMessage+8
#DEFINE TX_DATA4              TxMessage+9
;--------------------------------------------------------------------------------------
BOOTb     code
;--------------------------------------------------------------------------------------
	ORG	0x0000			; Re-map Reset vector
	bra	Setup	
	bra	Setup


	ORG	0x0008
VIntH
	bra	RVIntH			; Re-map Interrupt vector

	ORG	0x0018
VIntL
	bra	RVIntL			; Re-map Interrupt vector
;--------------------------------------------------------------------------------------

 

;--------------------------------------------------------------------------------------
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
;--------------------------------------------------------------------------------------
; Setup CAN registers.
;--------------------------------------------------------------------------------------
	bcf	TRISB, 2		; Setup cantx pin
	bsf	TRISB, 3		; Setup canrx pin
	
	bsf	TRISB, 4		; Setup canrs pin
	bcf	LATB, 4			; Setup canrs pin

	movlw	ECAN_CONFIG_MODE;
	movwf   CANCON;
WaitConfig
	movf	CANSTAT,W
	andlw   0xE0
	xorlw	ECAN_CONFIG_MODE
	bnz     WaitConfig
	

                ECANCON = ECAN_SET_FIFO_MODE;
                BSEL0   = ECAN_CONFIGURE_BUFFERS;

        // Set up mask 0 to receive broadcast messages. (GLOBAL_ADDRESS)
        RXM0SIDH = 0x07;
        RXM0SIDL = 0x88; //0x80;
        RXM0EIDH = 0x00;
        RXM0EIDL = 0x00;
        // Set up mask 1 to receive
        //         messages sent to the global address (or eventually us).
        RXM1SIDH = 0x00;
        RXM1SIDL = 0x08;
        RXM1EIDH = 0xFF;
        RXM1EIDL = 0x00;
        // Set up mask 2  (filter 15) to receive ALL messages. - GP
        RXF15SIDH = 0x00;
        RXF15SIDL = 0x08;
        RXF15EIDH = 0x00;
        RXF15EIDL = 0x00;

        // Set up filter 0 to accept only broadcast messages (PF = 240-255).
        // Set up filter 2 and 3 to accept only the global address.  Once we
        // get an address for the CA, we'll change filter 3 to accept that
        // address.
        RXF0SIDH = 0x07;
        RXF0SIDL = 0x88;
        RXF2SIDL = 0x08;
        RXF2EIDH = J1939_GLOBAL_ADDRESS;
        RXF3SIDL = 0x08;
        RXF3EIDH = J1939_GLOBAL_ADDRESS;

                // Set mask 0 to filter 0, and mask 1 to filters 2 and 3.
                MSEL0    = 0x5C;

                // Leave all filters set to RXB0.  The filters will apply to
                // all receive buffers.
                RXFBCON0  = 0x00;
                RXFBCON1  = 0x00;
                RXFBCON2  = 0x00;

                // Enable filters 0, 2, and 3.  Disable the others.
                RXFCON0  = 0x0D;
                RXFCON1  = 0x00;

        BRGCON1 = CanParam1.W;
        BRGCON2 = ECAN_BRGCON2;
        BRGCON3 = ECAN_BRGCON3;


        // Put the ECAN module into Normal Mode
        SetECANMode( ECAN_NORMAL_MODE );
void SetECANMode( unsigned char Mode )
{
        CANCON = Mode;
#if !defined __DEBUG
        while ((CANSTAT & 0xE0) != Mode);
#endif
}


        // Give the network management transmit buffer the highest priority.
        SET_NETWORK_WINDOW_BITS;
        MAPPED_CON = 0x03;














;--------------------------------------------------------------------------------------
    bcf     TRIS_LED
    bcf     BUS_OUT
    movlw	b'00110010'     ;
    movwf   T3CON
    bsf     T3CON,TMR3ON    ; timer start
	bcf     PIR2, TMR3IF    ; 32mS
    movlb   HIGH(timCtr)    ;// PER INDIRIZZARE DATA BANK
    clrf    timCtr
    clrf    timCtr+1
;--------------------------------------------------------------------------------------

    bsf     SYS_LED			; led acceso: in wait

;--------------------------------------------------------------------------------------
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
-->	rcall	RdRS232			; Get byte
	
    xorlw   0xF0
    bz      GoAhead           
    xorlw   0xF0 ^ 0x11
	bz      GoRepro
	bra 	StartOfLine		; Yes, start over	


GoRepro
    goto	REPROmainB


GoAhead
	bra		RVReset




























;-----------------------------------------------------------------------------
REPROmainB
        movlb   HIGH(RxMessage)          ;// PER INDIRIZZARE DATA BANK
 IFDEF REPRO_DEBUG
        call    Save_Context
 ENDIF
        clrf    LastTXBufferUsed;
        clrf    INTCON;                   // disable all interrupts
        clrf    CanCommand;
        clrf    FlashLength;
        clrf    iTimeout;
        clrf    iTimeout+1;
        clrf    iTimeout+2;
        clrf    ReproError;
        clrf    INTCON;                   // disable all interrupts

; versione 0B - recupera HostAddress e MyAddress dallo stack di chiamata caricati con POSTINC1
;               da call C  REPROmainB(HostAddress, MyAddress); (prima viene pushato MY e poi HOST)
; FSR1 dovrebbe puntare alla sommita' dello stack software
        movff   POSTDEC1, HostAddress   ; dummy - only for decrement
        movff   POSTDEC1, HostAddress
        movff   POSTDEC1, MyAddress

; // loop until command END-REPRO

;   while ( CanCommand != 0x80 )
ReproLoop
        clrwdt
;       switch (CanCommand)
        movf    CanCommand,w
        bz      ReproQuery         ; 0x00
        xorlw   0x80
        bz      ReproEnd           ; 0x80
        xorlw   0x80 ^ 0x01
        bz      ReproNewBlock      ; 0x01
        xorlw   0x01 ^ 0x02
        bz      ReproEndWrBlock    ; 0x02
        xorlw   0x02 ^ 0x03
        bz      ReproEndBlock      ; 0x03
        xorlw   0x03 ^ 0x40
        bz      ReproWriteBlock    ; 0x40
        bra     ReproLoopEnd

;-----------------------------------------------------------------------------
ReproQuery                         ; 0x00
        movlw   2
        movwf   TxMessage+4     ; txmessage.length
        clrf    TxMessage+5     ; txmessage.data[0]
        movlw   REPRO_VERSION;
        movwf   TxMessage+6     ; txmessage.data[1]
        call    REPRO_TransmitMessages
        clrf	crcseq		; inizializza la sequenza CRC

        bra     ReproLoopEnd

;-----------------------------------------------------------------------------
ReproNewBlock                      ; 0x01
;               //x01: new flash block binary mode - AA: address - L: data length (8-16-24-32-40-48-56-64)
        movff   RxMessage+6,FlashAddress     ; RxMessage.data[1]
        movff   RxMessage+7,FlashAddress+1   ; RxMessage.data[2]
        movff   RxMessage+8,FlashLength      ; RxMessage.data[3]
        clrf    FlashPtr
        clrf    CheckWord			; inizializzazione checkWord
        clrf    CheckWord+1			; inizializzazione checkWord
        lfsr    FSR0, FlashData        ; in fsr0 indirizzo flash buffer
        bra     ReproLoopEnd

;-----------------------------------------------------------------------------
ReproEndWrBlock                    ; 0x02
;;;;;   bcf     LATC,5          ;  LEDON
;               //x02: end flash block binary mode - CCKK: check-word (sum of values)
        movf    RxMessage+6,w                ; RxMessage-data[1]
        xorwf   CheckWord,w			; test di uguaglianza tra checkword ricevuto e calcolato
        bnz     ReproNoCheck
        movf    RxMessage+7,w                ; RxMessage-data[2]
        xorwf   CheckWord+1,w		; test di uguaglianza tra checkword ricevuto e calcolato
        bnz     ReproNoCheck

        movf    FlashAddress+1,w             ; Flash Address HB

#ifdef __18F25K80
        andlw   0x78
        xorlw   0x70
#else
        andlw   0xF8        ; // proteggere da F0 a F7 compresi
                            ; // = F0: protetto      diverso: scrivibile
        xorlw   0xF0
#endif

        bz      ReproProtect

        call    REPROwritePage
        clrf    TxMessage+6                  ; TxMessage-data[1]
        bra     ReproEndReply

ReproNoCheck
;;;;;   bsf     LATC,5          ;  LEDOFF
;;      movff   RxMessage+5,TxMessage+5      ; TxMessage-data[0]
        movlw   0xFF
        infsnz  ReproError,f
        movlw   0xFE
        movwf   TxMessage+6                  ; TxMessage-data[1]
        movff   RxMessage+6,TxMessage+7      ; CheckL previsto
        movff   RxMessage+7,TxMessage+8      ; CheckH previsto
        movff   CheckWord,TxMessage+9        ; CheckL calcolato
        movff   CheckWord+1,TxMessage+10     ; CheckH calcolato
        bra     ReproEndReply

ReproProtect
        movlw   0x01
        movwf   TxMessage+6                  ; TxMessage-data[1]
ReproEndReply

;-----------------------------------------------------------------------------
ReproEndBlock                      ; 0x03

        movlw   6
        movwf   TxMessage+4                  ; txmessage.length
        movff   RxMessage+5,TxMessage+5      ; txmessage.data[0]
        call    REPRO_TransmitMessages

        bra     ReproLoopEnd


;-----------------------------------------------------------------------------
ReproWriteBlock                    ; 0x40
ReproWriteBlockNewCRC              ; 0x40
;               //x40: flash data
        lfsr    FSR1, RxMessage+5      ; in fsr1 indirizzo Rx data
ReproWriteLoopCRC
        movf    POSTINC1,w                  ; rxmessage.data[x]
        movwf   POSTINC0			; deposita nel buffer di scrittura
        
		movwf	crcdep				; appoggia sul deposito CRC
		
		incf	crcseq,f			; incrementa la sequenza CRC
		movlw   0x07				; da 0 a 7
		andwf   crcseq,w			; numero di shift left
		movwf   crcnumr				;     in crcnumr
		bz      ReproWriteLoop0CRCok
		
ReproWriteLoop0CRC
		rlncf   crcdep,f			; shift left
		decf    crcnumr				;   da 1 a 8 volte
		bnz     ReproWriteLoop0CRC
ReproWriteLoop0CRCok
		movf    crcdep,w
		
        addwf   CheckWord,f				; calcolo checkWord SOMMA
        bnc     ReproWriteLoop1CRC
        incf    CheckWord+1,f			; calcolo checkWord SOMMA
ReproWriteLoop1CRC
        decf    FlashLength,f
        decf    RxMessage+4,f    ; rxmessage.length
        bnz     ReproWriteLoopCRC


;-----------------------------------------------------------------------------
ReproLoopEnd
;  // wait for next command - 16 x 256 x 256 x 256 = 16sec at 64mhz 
        clrwdt
        call    REPRO_ReceiveMessages
        xorlw   0
         bz     ReproLoopEnd1  ; retlw 0 : ok
        incf    iTimeout,f
        bnz     ReproLoopEnd
        incf    iTimeout+1,f
        bnz     ReproLoopEnd
        incf    iTimeout+2,f
        bnz     ReproLoopEnd

		bra     ReproEnd;   // timeout reset

;        clrf    FlashLength     ;     // timeout 4 mSec  x 15 = 60mSec
;        movlw   0x03
;        movwf   RxMessage+5     ; rxmessage.data[0]
;        movlw   0xFF
;        movwf   TxMessage+6     ; txmessage.data[1]
;        movwf   TxMessage+7     ; txmessage.data[2]
;        bra     ReproNoCheck

ReproLoopEnd1
        clrf    iTimeout
        clrf    iTimeout+1
        clrf    iTimeout+2
        movf    FlashLength,f
        bz      ReproLoopNewCmd
        movlw   0x40
        movwf   CanCommand
        bra     ReproLoop
ReproLoopNewCmd
        movff   RxMessage+5,CanCommand      ; Rxmessage.data[0]
        bra     ReproLoop

ReproEnd
        reset

; ---------------------------------------------------------------------------------


; ---------------------------------------------------------------------------------
REPROwritePage
    btfsc  EECON1,WR                  ;// wait for any eeprom write to finish
      bra  REPROwritePage

;   // set table pointer to desired page address....
    clrf   TBLPTRU                       ; // set up table pointer register (upper byte)
    movff  FlashAddress+1,TBLPTRH        ; // set up table pointer register (high byte)
    movff  FlashAddress,  TBLPTRL        ; // set up table pointer register (low byte)

;   // erase page....
    bsf    EECON1,EEPGD ;                  // point to flash code space
    bcf    EECON1,CFGS ;                   // do not access config space
    bsf    EECON1,WREN ;                   // enable write to memory
    bsf    EECON1,FREE ;                   // enable page erase operation
    movlw  0x55  ;                         // write entry sequence step 1
    movwf  EECON2;                         // write entry sequence step 1
    movlw  0xAA  ;                         // write entry sequence step 2
    movwf  EECON2;                         // write entry sequence step 2
    bsf    EECON1,WR ;                     // erase page of code memory (CPU stalls until complete)
    nop  ;                                 // NOP instruction immediately after CPU stall

REPROwritePageW1
    btfsc  EECON1,WR                  ;// wait for any eeprom write to finish
      bra  REPROwritePageW1

;   // set up starting addresses (FSR0 & TBLPTR)....
    lfsr    FSR0, FlashData              ; in fsr0 indirizzo flash buffer
    TBLRD*-                              ; // dummy table read decrements TBLPTR
    movlw   32
    movwf   i

REPROwritePage1
;   // fill holding registers from data array (for 1st half-page write)....
        movf    POSTINC0,w               ; rxmessage.data[x]
        movwf   TABLAT                   ; // move byte from data array to TABLAT register
        TBLWT+*                          ; // write data from TABLAT into holding register
        decfsz  i,f
         bra    REPROwritePage1

;// write 1st half-page to flash....
    bsf    EECON1,EEPGD ;                  // point to flash code space
    bcf    EECON1,CFGS ;                   // do not access config space
    bsf    EECON1,WREN ;                   // enable write to memory
    movlw  0x55  ;                         // write entry sequence step 1
    movwf  EECON2;                         // write entry sequence step 1
    movlw  0xAA  ;                         // write entry sequence step 2
    movwf  EECON2;                         // write entry sequence step 2
    bsf    EECON1,WR ;                     // erase page of code memory (CPU stalls until complete)
    nop  ;                                 // NOP instruction immediately after CPU stall

REPROwritePageW2
    btfsc  EECON1,WR                  ;// wait for any eeprom write to finish
      bra  REPROwritePageW2

    movlw   32
    movwf   i

REPROwritePage2
;   // fill holding registers from data array (for 2st half-page write)....
        movf    POSTINC0,w                  ; rxmessage.data[x]
        movwf   TABLAT     ;                 // move byte from data array to TABLAT register
        TBLWT+*            ;                 // write data from TABLAT into holding register
        decfsz  i,f
         bra    REPROwritePage2

;   // write 2nd half-page to flash....
    bsf    EECON1,EEPGD ;                  // point to flash code space
    bcf    EECON1,CFGS ;                   // do not access config space
    bsf    EECON1,WREN ;                   // enable write to memory
    movlw  0x55  ;                         // write entry sequence step 1
    movwf  EECON2;                         // write entry sequence step 1
    movlw  0xAA  ;                         // write entry sequence step 2
    movwf  EECON2;                         // write entry sequence step 2
    bsf    EECON1,WR ;                     // erase page of code memory (CPU stalls until complete)
    nop  ;                                 // NOP instruction immediately after CPU stall

REPROwritePageW3
    btfsc  EECON1,WR                  ;// wait for any eeprom write to finish
      bra  REPROwritePageW3

    bcf    EECON1,WREN ;                   // disable write to memory
    return
; ---------------------------------------------------------------------------------


; ---------------------------------------------------------------------------------
REPRO_ReceiveMessages

    clrf   RxRC
;       if (COMSTAT & FIFOEMPTY_MASK)                // Repeat until the FIFO is empty
    btfss  COMSTAT,NOT_FIFOEMPTY
      bra  Repro_Receive_null

;               // Set the Window Address bits to the message buffer
;               ECANCON = ECAN_SET_FIFO_MODE | ECAN_SELECT_RX_BUFFER | (CANCON & 0x07);
    movf   CANCON,w
    andlw  0x07
    iorlw  0xB0 ;         ECAN_SET_FIFO_MODE | ECAN_SELECT_RX_BUFFER  ; 0xA0 | 0x10
    movwf  ECANCON

;               // Read a message from the mapped receive buffer.
;               RegPtr = &MAPPED_SIDH;

    lfsr    FSR1, MAPPED_SIDH      ; in fsr1 indirizzo RegData
    lfsr    FSR2, RxMessage        ; in fsr2 indirizzo Rx data
    movlw   13
    movwf   i

REPRO_ReceiveMessages1
    movff   POSTINC1,POSTINC2
    decfsz  i,f
     bra    REPRO_ReceiveMessages1
;;;;;   bsf     LATC,5          ;  LEDOFF

;               // Clear any receive flags
    bcf     MAPPED_CON,RXFUL
    movlb   HIGH(RXB1CON)
    bcf     RXB1CON,RXFUL

    movlb   HIGH(B0CON)                ;// PER INDIRIZZARE SFR  BANK 0xEnn
    bcf     B0CON,RXFUL
    bcf     B1CON,RXFUL
    bcf     B2CON,RXFUL
    bcf     B3CON,RXFUL
    bcf     B4CON,RXFUL
    bcf     B5CON,RXFUL

;               // Errata DS80162B section 6, try to clear the FIFO Empty flag
;               COMSTAT &= ~FIFOEMPTY_MASK;
    movlb   HIGH(RxMessage)          ;// PER INDIRIZZARE DATA BANK
    bcf     COMSTAT,NOT_FIFOEMPTY
    nop
    bcf     COMSTAT,NOT_FIFOEMPTY

;               // Format the PDU Format portion so it's easier to work with.
;               Loop = (RxMessage.PDUFormat & 0xE0) >> 3;                       // Get SID2-0 ready.
    movf    RxMessage+1,w               ; PDUFormat
    andlw   0xE0
    movwf   temp
    rrncf   temp,f ; il bit che esce a dx rientra a sx
    rrncf   temp,f ; ma non importa perche' i 3 bit di
    rrncf   temp,f ; dx sono stati azzerati

;               RxMessage.PDUFormat = (RxMessage.PDUFormat & 0x03) |
;                                                             Loop |
;                                 ((RxMessage.PDUFormat_Top & 0x07) << 5);
    movf    RxMessage+1,w               ; PDUFormat
    andlw   0x03
    iorwf   temp,w
    movwf   RxMessage+1                 ; PDUFormat

    movlw   0x07
    andwf   RxMessage,f                 ; PDUFormat_Top
    rlncf   RxMessage,f ; il bit che esce a sx rientra a dx
    rlncf   RxMessage,f ; ma non importa perche' i 5 bit di
    rlncf   RxMessage,f ; sx sono stati azzerati
    rlncf   RxMessage,f
    rlncf   RxMessage,w
    iorwf   RxMessage+1,f               ; PDUFormat

    movf    RxMessage+1,w               ; PDUFormat
    xorlw   CMD_FIRMWARE
    bnz     Repro_Receive_false

    movf    RxMessage+2,w               ; PDUSpecific (destination)
    xorwf   MyAddress,w
    bnz     Repro_Receive_false

    retlw 0x00

Repro_Receive_false
	bra	  REPRO_ReceiveMessages
	
;    movlw 0x01
;    movwf RxRC
;    retlw 0x01

Repro_Receive_null
    movlw 0xFF
    movwf RxRC
    retlw 0xFF
; ---------------------------------------------------------------------------------



; ---------------------------------------------------------------------------------
REPRO_TransmitMessages
;       // Make sure the last buffer we used last time is done transmitting.
;       // This should be redundant if we're using interrupts, but it is required if
;       // we're polling.  If the last buffer is done, then reset our buffer pointer
;       // to the beginning of the buffer list.

    movf    LastTXBufferUsed,w
    bz      REPRO_TransmitMessages1
;       while (LastTXBufferUsed != 0)
;       {
;               ECANCON = BUFFER_TABLE[LastTXBufferUsed-1].WindowBits;
    movlw   0x84
    movwf   ECANCON
    btfsc   MAPPED_CON,MAPPED_TXREQ
      bra   REPRO_TransmitMessages
    clrf    LastTXBufferUsed
;               if (!MAPPED_CONbits.MAPPED_TXREQ)
;                       LastTXBufferUsed = 0;
;       }

REPRO_TransmitMessages1
;       // All transmit buffers are available, so fill them up.
;               ECANCON = BUFFER_TABLE[LastTXBufferUsed].WindowBits;
    movlw   0x84
    movwf   ECANCON
;               if (!MAPPED_CONbits.MAPPED_TXREQ)       // make sure buffer is free
;               {
    btfsc   MAPPED_CON,MAPPED_TXREQ
      bra   REPRO_TransmitMessages

    movlw   0xC0
    movwf   TxMessage               ; priority = 3
    movff   HostAddress,TxMessage+2 ; destination
    movlw   CMD_FIRMWARE
    movwf   TxMessage+1             ; pduformat
    movff   MyAddress,TxMessage+3   ; sourceaddress

    call    SendCanMessage
    incf    LastTXBufferUsed,f
    return
; ---------------------------------------------------------------------------------



; ---------------------------------------------------------------------------------
SendCanMessage
;       // Set up the final pieces of the message

;       // Put PDUFormat into the structure to match the J1939-CAN format.  This
;       // involves splitting the original value in PDUFormat into two pieces,
;       // leaving some holes for the TXBnSIDL register, and setting the EXIDE bit.

;    // Put the top three bits into SID5-3

;       MsgPtr->PDUFormat_Top = MsgPtr->PDUFormat >> 5;
    movf    TxMessage+1,w               ; save PDUFormat
    andlw   0xE0         ; per azzerare i 5 bit di dx
    movwf   temp
    rrncf   temp,f                      ; >>5
    rrncf   temp,f                      ; >>5
    rrncf   temp,f                      ; >>5
    rrncf   temp,f                      ; >>5
    rrncf   temp,w                      ; >>5
    iorwf   TxMessage,f                 ; PDUFormat_Top
;    // Save the bottom two bits.
;       Temp = MsgPtr->PDUFormat & 0x03;
    movf    TxMessage+1,w               ; PDUFormat
    andlw   0x03
    movwf   temp
;    // Move up bits 4-2 into SID2-0.
;       MsgPtr->PDUFormat = (MsgPtr->PDUFormat & 0x1C) << 3;
    movf    TxMessage+1,w               ; PDUFormat
    andlw   0x1C
    movwf   TxMessage+1                 ; PDUFormat
    rlncf   TxMessage+1,f
    rlncf   TxMessage+1,f
    rlncf   TxMessage+1,f
;    // Put back EID17-16, set EXIDE.
;       MsgPtr->PDUFormat |= Temp | 0x08;
    movf    temp,w                      ; PDUFormat
    iorlw   0x08
    iorwf   TxMessage+1,f               ; PDUFormat
;       // Wait until the requested buffer can be used to transmit.  We shouldn't
;       // need a time-out here unless something else in the design isn't working
;       // (or we have to send a LOT of network management messages).
SendCanMessage_wait
;       while (MAPPED_CONbits.MAPPED_TXREQ);
    btfsc   MAPPED_CON,MAPPED_TXREQ
      bra   SendCanMessage_wait
;       // Load the message buffer.  Load the first 5 bytes of the message,
;       // then load whatever part of the data is necessary.

;       RegPtr = &MAPPED_SIDH;
;       Loop = 0;
;       for (Loop=0; Loop<J1939_MSG_LENGTH+MsgPtr->DataLength;  Loop++, RegPtr++)
;               *RegPtr = MsgPtr->Array[Loop];

    lfsr    FSR1, TxMessage        ; in fsr2 indirizzo Rx data
    lfsr    FSR2, MAPPED_SIDH      ; in fsr1 indirizzo RegData
    movlw   13
    movwf   i

SendCanMessages_loop
;   movff   POSTINC1,POSTINC2
    movf    POSTINC1,w
    movwf   POSTINC2
    decfsz  i,f
     bra    SendCanMessages_loop

;       // Now tell the module to send the message.
;       MAPPED_CONbits.MAPPED_TXREQ = 1;
    bsf     MAPPED_CON,MAPPED_TXREQ
    return

 IFDEF REPRO_DEBUG
Save_Context
    movff    FSR0H,saveFSR0H
    movff    FSR0L,saveFSR0L
    movff    FSR1H,saveFSR1H
    movff    FSR1L,saveFSR1L
    movff    FSR2H,saveFSR2H
    movff    FSR2L,saveFSR2L
    return

Restore_Context
    movff    saveFSR0H,FSR0H
    movff    saveFSR0L,FSR0L
    movff    saveFSR1H,FSR1H
    movff    saveFSR1L,FSR1L
    movff    saveFSR2H,FSR2H
    movff    saveFSR2L,FSR2L
    return
; ---------------------------------------------------------------------------------
REPRO_TestReceiveMessages
    movlb   HIGH(RxMessage)          ;// PER INDIRIZZARE DATA BANK
    call    Save_Context
    call    REPRO_ReceiveMessages
    call    Restore_Context
    return

 ENDIF

 IFDEF L_OUT_SERIAL

;**************************************************************************************
; Standard serial transmit at 38400 BPS thru PGD  - bitlen 26uS
; 38400  is 52  cycles at 8 MHz
; 38400  is 208 cycles at 32MHz
;**************************************************************************************
serial_send                                             ; 38.4  mode
                movwf           Ser_OUT
                movlw           .9                      ; set up loop ctr
                movwf           BitCnt
                bra             Ser_clear               ; start with START bit

Ser_lp          rrcf            Ser_OUT,F               ; 49
                btfsc           STATUS,C                ; 50
                  bra           Ser_set                 ; 51..52
Ser_clear       bcf             OUT_SERIAL              ; 0
                bra             Ser_next                ; 1..2
Ser_set         bsf             OUT_SERIAL              ; 0
                bra             Ser_next                ; 1..2
Ser_next                                                ; 3
 IF FREQUENZA == .8000
                movlw           .12                     ; 3   (52-16 : 3= 12
 ENDIF
 IF FREQUENZA == .32000
                movlw           .63                     ; 3   (208-16 : 3= 64
 ENDIF
                call            Delay ; *3+5            ; 4..43
                nop                                     ; 44
                nop                                     ; 45
                decfsz          BitCnt,F                ; 46
                  bra           Ser_lp                  ; 47..48
                nop                                     ; 48
                nop                                     ; 49
                nop                                     ; 50
                nop                                     ; 51
                bsf             OUT_SERIAL              ; 0
                nop
 IF FREQUENZA == .8000
                movlw           .20                     ; 1 stopBIT
 ENDIF
 IF FREQUENZA == .32000
                movlw           .100                    ; 1 stopBIT
 ENDIF
                call            Delay ; *3+5            ; 2..26
                return
;**************************************************************************************
; Delay for 3n+5 (including call/return)
Delay           movwf           TMP
Delaylp         decfsz          TMP,F
                  bra           Delaylp
                return
;**************************************************************************************

 ENDIF

        end

