/*
  Skein block functions in ARMv7 assembly code.

  Implemented according to ``The Skein Hash Function Family'' version 1.3

  Changes:
    2011-07-09: Made code ARMv5TE compatible.
    2011-07-09: Implemented Skein-256.

  Author: Håkon Haugdal Hitland <haakhi@gmail.com>
  Year: 2011

  The author waives all copyright and related or neighbouring rights to
  this code to the extent possible under law.
  Anyone may use, redistribute and modify this code in any way and for any
  purpose, without restrictions.
  This software is distributed without any warranty. No guarantee is given
  for its correctness.
*/

	.arch armv5te
	.syntax unified
	.altmacro
	.text

#ifndef SKEIN_USE_ASM
#define SKEIN_USE_ASM (256)
#endif

#if SKEIN_USE_ASM & 512 || SKEIN_USE_ASM & 1024
#error Skein-512 and Skein-1024 not implemented.
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

/*
 * Basic double-MIX round.
 * The instructions are arranged for dual-issuing, doing the MIX computations
 * in parallel.
 * r1:r0 and r5:r4 holds v0 and v2.
 * r3:r2 and r7:r6 are alternatingly v1 and v3.
 */
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

/*
 * Round seven has rotation constants of 32, which saves a cycle on the
 * rotation. One could probably save another cycle by alternatingly running
 * 8 mirrored rounds with r2<->r3, r6<->r7 swapped.
 */
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
	/* Separate odd and even rounds */
	.if \round == 7
	S256_Round7 /* Special case round 7 */
	.elseif \round && 1
	S256_RoundBase \round, r4, r5, r0, r1, 1, 0
	.else
	S256_RoundBase \round, r0, r1, r4, r5, 0, 1
	.endif
.endm

.macro S256_InjectKey subkey
/* Calculate tweak and key addresses */
TWEAK1_ADR = S256_SOFS_TWEAKSCHED + 8 * ((\subkey + 1) % 3)
KEY0_ADR = S256_SOFS_KEYSCHED + 8 * ((\subkey) % 5)
KEY1_ADR = S256_SOFS_KEYSCHED + 8 * ((\subkey + 1) % 5)
KEY2_ADR = S256_SOFS_KEYSCHED + 8 * ((\subkey + 2) % 5)
KEY3_ADR = S256_SOFS_KEYSCHED + 8 * ((\subkey + 3) % 5)

	/* t0 is left in r11:r10 from previous key round */
	ldr r8, [sp, KEY0_ADR]

	ldr r9, [sp, KEY0_ADR + 4]
	adds r2, r10

	ldr r10, [sp, KEY1_ADR]
	adc r3, r11 /* v1 += t0 */

	ldr r11, [sp, KEY1_ADR + 4] /* k0,k1 -> r9:r8, r11:r10 */
	adds r0, r8

	ldr r8, [sp, KEY2_ADR]
	adc r1, r9 /* v0 += k0 */

	ldr r9, [sp, KEY2_ADR + 4]
	adds r2, r10

	ldr r10, [sp, KEY3_ADR]
	adc r3, r11 /* v1 += k1 */

	ldr r11, [sp, KEY3_ADR + 4] /* k2,k3 -> r9:r8, r11:r10 */
	adds r4, r8

	adc r5, r9 /* v2 += k2 */
	adds r6, r10

	adc r7, r11 /* v3 += k3 */
	ldr r10, [sp, TWEAK1_ADR]

	ldr r11, [sp, TWEAK1_ADR + 4] /* t1 -> r11:r10 */
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

/* Stack offsets */
S256_SOFS_KEYSCHED = 0
S256_SOFS_TWEAKSCHED = S256_SOFS_KEYSCHED + (8 * 5)
S256_SOFS_CTX = S256_SOFS_TWEAKSCHED + (8 * 3)
S256_SOFS_BLKPTR = S256_SOFS_CTX + 4
S256_SOFS_BLKCNT = S256_SOFS_BLKPTR + 4
S256_SOFS_BYTECNTADD = S256_SOFS_BLKCNT + 4

/* Constants */
.S256C_C240:
	.word SKEIN_KS_C240_LOW, SKEIN_KS_C240_HIGH

/* void Skein_256_Process_Block(Skein_256_Ctxt_t *ctx, const u08b_t *blkPtr, size_t blkCnt, size_t byteCntAdd); */
/*
 * Register usage:
 * r0-r7: State v0-v3
 * r8-r11: Temporary registers, keys, plaintext, etc.
 * r12, Temporary values, addresses, blkPtr.
 *
 * Stack contents:
 * S256_SOFS_KEYSCHED (5 * 8): Key schedule k0-k4
 * S256_SOFS_TWEAKSCHED (3 * 8): Tweak schedule t0-t2
 * S256_SOFS_CTX (1 * 4): Pointer to tweak and state
 * S256_SOFS_BLKPTR (1 * 4): Pointer to plaintext
 * S256_SOFS_BLKCNT (1 * 4): Remaining block counter
 * S256_SOFS_BYTECNTADD (1 * 4): byteCntAdd
 */

	.balign 8
	.global Skein_256_Process_Block
Skein_256_Process_Block:
	add r0, CTX_TWEAK_OFS
	push {r0-r11}
	sub sp, 8 * (5 + 3) /* Locate space for tweak and key schedules */

	ldm r0!, {r8-r11} /* t0,t1 -> r8-r11 */
	ldm r0, {r0-r7} /* k0-k3 -> r0-r7 */

0:
	/* Calculate and store tweaks */
	ldr r12, [sp, S256_SOFS_BYTECNTADD] /* byteCntAdd -> r6 */
	str r10, [sp, S256_SOFS_TWEAKSCHED + 8]
	str r11, [sp, S256_SOFS_TWEAKSCHED + 12] /* Store t1 */
	adds r8, r12
	str r8, [sp, S256_SOFS_TWEAKSCHED]
	adc r9, 0 /* t0 += byteCntAdd */
	str r9, [sp, S256_SOFS_TWEAKSCHED + 4] /* Store t0 */
	eor r8, r10
	eor r9, r11 /* t2 -> r9:r8 */
	str r8, [sp, S256_SOFS_TWEAKSCHED + 16]
	str r9, [sp, S256_SOFS_TWEAKSCHED + 20] /* Store t2 */
	
	/* Calculate and store key */
	eor r8, r0, r2
	eor r9, r1, r3
	eor r8, r4
	ldr r10, .S256C_C240
	add r12, sp, S256_SOFS_KEYSCHED
	ldr r11, .S256C_C240 + 4 /* C240 -> r11:r10 */
	eor r9, r5
	eor r8, r6
	eor r9, r7
	eor r8, r10
	eor r9, r11 /* k4 -> r9:r8 */
	ldr r11, [sp, S256_SOFS_BLKPTR] /* blkPtr -> r11; Prepare for reading plaintext */
	stm r12, {r0-r9} /* Store k0-k4 */

	/* Initial key injection */
	/* Add plaintext */
	mov r12, r11
	ldr r8, [r11, 0]
	ldr r9, [r11, 4]
	ldr r10, [r11, 8]
	adds r0, r8
	ldr r11, [r11, 12] /* p0,p1 -> r8-r11 */
	adc r1, r9
	ldr r8, [r12, 16]
	adds r2, r10
	ldr r9, [r12, 20]
	adc r3, r11 /* v0,v1 += p0,p1 */
	ldr r10, [r12, 24]
	adds r4, r8
	ldr r11, [r12, 28] /* p2,p3 -> r8-r11 */
	adc r5, r9
	ldr r8, [sp, S256_SOFS_TWEAKSCHED]
	adds r6, r10
	ldr r9, [sp, S256_SOFS_TWEAKSCHED + 4]
	adc r7, r11 /* v2,v3 += p2,p3 */
	ldr r10, [sp, S256_SOFS_TWEAKSCHED + 8]
	adds r2, r8
	ldr r11, [sp, S256_SOFS_TWEAKSCHED + 12]
	adc r3, r9 /* v1 += t0 */
	adds r4, r10
	adc r5, r11 /* v2 += t1 */
	
	/* Do 72 MIX rounds */
	.irp round, 0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68
	S256_Four_Rounds \round
	.endr

	/* Xor state with plaintext to get new key */
	ldr r8, [r12]
	ldr r9, [r12, 4]
	ldr r10, [r12, 8]
	eor r0, r8
	ldr r11, [r12, 12] /* p0,p1 -> r8-r11 */
	eor r1, r9
	ldr r8, [r12, 16]
	eor r2, r10
	ldr r9, [r12, 20]
	eor r3, r11 /* v0,v1 ^= p0,p1 */
	ldr r10, [r12, 24]
	eor r4, r8
	ldr r11, [r12, 28]
	eor r5, r9
	add r12, 32 /* blkPtr += 32 */
	eor r6, r10
	str r12, [sp, S256_SOFS_BLKPTR] /* Store new blkPtr */
	eor r7, r11 /* v2,v3 ^= p2,p2 */

	/* Load tweaks */
	ldr r12, [sp, S256_SOFS_BLKCNT] /* blkCnt -> r12 */
	ldrd r10, r11, [sp, S256_SOFS_TWEAKSCHED + 8]
	ldrd r8, r9, [sp, S256_SOFS_TWEAKSCHED] /* t0,t1 -> r8-r11 */
	bic r11, 1 << (SKEIN_T1_FIRST_FLAG - 32) /* Clear 'first' flag from t1 */

	/* Loop if more blocks */
	subs r12, 1
	str r12, [sp, S256_SOFS_BLKCNT]
	bne 0b


	/* Done, save tweak and key */
	ldr r12, [sp, S256_SOFS_CTX]
	stm r12!, {r8-r11} /* Store tweak */
	stm r12, {r0-r7} /* Store key */

	add sp, 4*4 + 8 * (5 + 3)
	pop {r4-r11}
	bx lr
	
#ifdef SKEIN_CODE_SIZE
/* size_t  Skein_256_Process_Block_CodeSize(void);
*/
	.global Skein_256_Process_Block_CodeSize
Skein_256_Process_Block_CodeSize:
	ldr r0, =$(Skein_256_Process_Block_CodeSize - Skein_256_Process_Block)
	bx lr

	.global Skein_256_Unroll_Cnt
Skein_256_Unroll_Cnt:
	mov r0, 0
	bx lr
#endif
#endif /* 256 */
