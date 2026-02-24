*---------------------------------------------------------------------*
* Register tracking test file                                         *
*---------------------------------------------------------------------*
TESTREG  CSECT
*
* Register declarations
*
BASE     EQUREG R12,A              Base register (address)
WORK     EQUREG R3,G               Work register (general)
FPR      EQUREG R0,F               Float register
CTLR     EQUREG R1,C               Control register
*
         USING TESTREG,BASE
*
* Valid usage
*
         LA    BASE,0              Address register in LA - ok
         LR    WORK,R2             General register in LR - ok
         LE    FPR,=E'1.0'         Float register in LE - ok
*
* Type mismatches (should warn)
*
         LE    WORK,=E'1.0'        General in float instr - mismatch
         LA    FPR,0               Float in address instr - mismatch
*
* Undeclared register (should warn)
*
         LR    MYSTERY,R5          MYSTERY not declared
*
* Labels
*
LOOP     DS    0H
         BCT   WORK,LOOP
         B     EXIT
EXIT     DS    0H
*
         END   TESTREG
