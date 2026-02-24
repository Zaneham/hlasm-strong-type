*---------------------------------------------------------------------*
* Sample HLASM program to test the extension                          *
*---------------------------------------------------------------------*
SAMPLE   CSECT
*
* Register declarations using Bixoft EQUREG
*
BASE     EQUREG R12,A              Base register
WORK     EQUREG R3,G               Work register
*
         USING SAMPLE,BASE
         USING IHADCB,R10          DCB addressability
*
* Structured programming example
*
         IF    (R1,EQ,0)
         LA    R2,100
         ELSE
         LA    R2,200
         ENDIF
*
* Loop example
*
         DO    WHILE=(WORK,GT,0)
         BCTR  WORK,0
         ENDDO
*
* Access DCB fields - hover over these!
*
         LH    R5,DCBBLKSI         Block size
         LH    R6,DCBLRECL         Record length
         TM    DCBOFLGS,DCBOFOPN   Check if open
         CLI   DCBRECFM,DCBRECF    Fixed format?
*
* Check register types
*
         CHKREG R12,A              Verify base register type
         CHKNUM 100,0,255          Validate numeric range
*
* Program structure
*
         PGM   SAMPLE
*
         END   SAMPLE
