/*
  Skein block functions in ARMv7 assembly code without SIMD.
  Implemented according to ``The Skein Hash Function Family'' version 1.3
*/

	.arch armv7a
	.syntax unified
	.altmacro
	.text

#ifndef SKEIN_USE_ASM
#define SKEIN_USE_ASM (256+512+1024)
#endif

SKEIN_KS_C240_LOW = 0xA9FC1A22
SKEIN_KS_C240_HIGH = 0x1BD11BDA
SKEIN_T1_FIRST_FLAG = (126 - 64)

/* rotation constants for Skein */
RC_256_0_0  = 14
RC_256_0_1  = 16

RC_256_1_0  = 52
RC_256_1_1  = 57

RC_256_2_0  = 23
RC_256_2_1  = 40

RC_256_3_0  =  5
RC_256_3_1  = 37

RC_256_4_0  = 25
RC_256_4_1  = 33

RC_256_5_0  = 46
RC_256_5_1  = 12

RC_256_6_0  = 58
RC_256_6_1  = 22

RC_256_7_0  = 32
RC_256_7_1  = 32


CTX_TWEAK_OFS = 8

#if SKEIN_USE_ASM & 256

/* Quarter of a 64-bit rotate + xor -- equal sides */
.macro rot_eor1 dest, reg1, reg2, rotation
	.if \rotation < 32
	eor \dest, \reg1, \reg2, lsl \rotation
	.elseif \rotation > 32
	eor \dest, \reg1, \reg2, lsr 64 - \rotation
	.endif
	/* Drop if == 32 */
.endm

/* Quarter of a 64-bit rotate + xor -- opposing sides */
.macro rot_eor2 dest, reg1, reg2, rotation
	.if \rotation < 32
	eor \dest, \reg1, \reg2, lsr 32 - \rotation
	.else
	eor \dest, \reg1, \reg2, lsl \rotation - 32
	.endif
.endm

.macro S256_RoundBase round, even0_0, even0_1, even1_0, even1_1, rot0, rot1
	adds \even0_0, r2

	adc \even0_1, r3 /* v0 / v2 -> even0 */
	adds \even1_0, r6

	rot_eor2 r8, \even0_1, r2, RC_256_\round\()_\rot0
	adc \even1_1, r7 /* v2 / v0 -> even1 */

	rot_eor1 r2, \even0_0, r2, RC_256_\round\()_\rot0
	rot_eor2 r9, \even1_1, r6, RC_256_\round\()_\rot1

	rot_eor2 r2, r2, r3, RC_256_\round\()_\rot0
	rot_eor1 r6, \even1_0, r6, RC_256_\round\()_\rot1

	rot_eor1 r3, r8, r3, RC_256_\round\()_\rot0 /* v1/v3 -> r3:r2 */
	rot_eor2 r6, r6, r7, RC_256_\round\()_\rot1

	rot_eor1 r7, r9, r7, RC_256_\round\()_\rot1 /* v3/v1 -> r7:r6 */
.endm

/* Round seven has rotation constants of 32, which saves a cycle on the rotation */
/* Todo: try saving additional cycle by unswapping in the key injection */
.macro S256_Round7
	adds r4, r2

	adc r5, r3 /* v0 / v2 -> r5:r4 */
	adds r0, r6

	eor r8, r4, r3
	adc r1, r7 /* v2 / v0 -> r1:r0 */

	eor r3, r2, r5
	eor r9, r0, r7

	mov r2, r8 /* v1/v3 -> r3:r2 */
	eor r7, r6, r1

	mov r6, r9 /* v3/v1 -> r7:r6 */

.endm

.macro S256_Round round
	/* Sepate odd and even rounds */
	.if \round == 7
	S256_Round7 /* Special case round 7 */
	.elseif \round && 1
	S256_RoundBase \round, r4, r5, r0, r1, 1, 0
	.else
	S256_RoundBase \round, r0, r1, r4, r5, 0, 1
	.endif
.endm

.macro S256_InjectKey subkey
	adds r2, r10

	adc r3, r11 /* v1 += t0 */
	add r12, sp, S256_SOFS_KEYSCHED + 8 * (\subkey % 5) /* load key position */

	ldm r12!, {r8-r11} /* k0,k1 -> r9:r8, r11:r10 */
	adds r0, r8

	adc r1, r9 /* v0 += k0 */
	adds r2, r10

	adc r3, r11 /* v1 += k1 */
	/**/

	ldm r12!, {r8-r11} /* k2,k3 -> r9:r8, r11:r10 */
	adds r4, r8

	adc r5, r9 /* v2 += k2 */
	adds r6, r10

	adc r7, r11 /* v3 += k3 */
	/**/

	ldrd r10, r11, [sp, (S256_SOFS_TWEAKSCHED) + 8 * ((\subkey + 1) % 3)] /* t1 -> r11:r10 */
	adds r6, \subkey

	adc r7, 0 /* v4 += s */
	adds r4, r10

	adc r5, r11 /* v3 += t1 */
.endm

.macro S256_Four_Rounds round
	S256_Round %((\round + 0) % 8)
	S256_Round %((\round + 1) % 8)
	S256_Round %((\round + 2) % 8)
	S256_Round %((\round + 3) % 8)

	S256_InjectKey %(\round / 4 + 1)
.endm


S256_SOFS_KEYSCHED = 0
S256_SOFS_TWEAKSCHED = S256_SOFS_KEYSCHED + (8 * 8)
S256_SOFS_CTX = S256_SOFS_TWEAKSCHED + (8 * 3)
S256_SOFS_BLKPTR = S256_SOFS_CTX + 4
S256_SOFS_BLKCNT = S256_SOFS_BLKPTR + 4
S256_SOFS_BYTECNTADD = S256_SOFS_BLKCNT + 4

/* Constants */
.S256C_C240:
	.word SKEIN_KS_C240_LOW, SKEIN_KS_C240_HIGH


	.balign 4
	.global Skein_256_Process_Block
Skein_256_Process_Block:
	add r0, CTX_TWEAK_OFS
	push {r0-r11}
	sub sp, 8 * (8 + 3) /* Locate space for tweak and key schedules */

	ldm r0!, {r8-r11} /* t0,t1 -> r8-r11 */
	ldm r0, {r0-r7} /* k0-k3 -> r0-r7 */

0:
	/* Calculate and store tweaks */
	ldr r12, [sp, S256_SOFS_BYTECNTADD] /* byteCntAdd -> r6 */
	/**/
	adds r8, r12
	/**/
	adc r9, 0
	add r12, sp, S256_SOFS_TWEAKSCHED
	stm r12!, {r8-r11} /* Store t0-t1 */
	eor r8, r10
	eor r9, r11
	strd r8, r9, [r12] /* Store t2 */
	
	/* Calculate and store key */
	eor r8, r0, r2
	eor r9, r1, r3
	eor r8, r4
	ldrd r10, r11, .S256C_C240 /* C240 -> r11:r10 */
	add r12, sp, S256_SOFS_KEYSCHED
	eor r9, r5
	eor r8, r6
	eor r9, r7
	eor r8, r10
	eor r9, r11 /* k4 -> r12:r11 */
	stm r12!, {r0-r9} /* Store k0-k4 */
	stm r12, {r0-r5} /* Store k0-k2 */

	/* Initial key injection */
	/* Add plaintext */
	ldr r12, [sp, S256_SOFS_BLKPTR]
	/**/
	ldm r12!, {r8-r11} /* p0,p1 -> r8-r11 */
	/**/
	adds r0, r8
	adc r1, r9
	adds r2, r10
	adc r3, r11
	ldm r12, {r8-r11} /* p2,p3 -> r8-r11 */
	adds r4, r8
	adc r5, r9
	adds r6, r10
	adc r7, r11

	add r12, sp, S256_SOFS_TWEAKSCHED
	/**/
	ldm r12, {r8-r11} /* t0, t1 -> r8-r11 */
	/**/
	adds r2, r8
	adc r3, r9 /* v1 += t0 */
	adds r4, r10
	adc r5, r11 /* v2 += t1 */
	
	.irp round, 0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68
	S256_Four_Rounds \round
	.endr

	/* Xor state with plaintext to get new key */
	ldr r12, [sp, S256_SOFS_BLKPTR]
	/**/
	ldm r12!, {r8-r11} /* p0,p1 -> r8-r11 */
	/**/
	eor r0, r8
	eor r1, r9
	eor r2, r10
	eor r3, r11
	ldm r12!, {r8-r11} /* p2,p3 -> r8-r11 */
	eor r4, r8
	eor r5, r9
	str r12, [sp, S256_SOFS_BLKPTR] /* Store new blkPtr */
	eor r6, r10
	eor r7, r11

	/* Load tweaks */
	add r12, sp, S256_SOFS_TWEAKSCHED
	ldm r12, {r8-r11} /* t0,t1 -> r8-r11 */

	ldr r12, [sp, S256_SOFS_BLKCNT] /* blkCnt -> r12 */
	bfc r11, (SKEIN_T1_FIRST_FLAG - 32), 1 /* Clear first flag from t1 */
	ldrd r8, r9, [sp, S256_SOFS_TWEAKSCHED] /* t0 -> r9:r8 */

	/* Loop if more blocks */
	subs r12, 1
	str r12, [sp, S256_SOFS_BLKCNT]
	bne 0b


	/* Done, save tweak and key */
	ldr r12, [sp, S256_SOFS_CTX]
	/**/
	stm r12!, {r8-r11} /* Store tweak */
	stm r12, {r0-r7} /* Store key */

	add sp, 4*4 + 8 * (8 + 3)
	pop {r4-r11}
	bx lr
	
#endif /* 256 */
