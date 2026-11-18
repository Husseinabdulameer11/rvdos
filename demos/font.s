	.file	"font.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.globl	FONT
	.section	.rodata
	.align	2
	.type	FONT, @object
	.size	FONT, 56
FONT:
	.byte	32
	.base64	"AAAAAAAAAA=="
	.byte	45
	.base64	"AAAAHwAAAA=="
	.byte	67
	.base64	"DxAQEBAQDw=="
	.byte	73
	.base64	"HwQEBAQEHw=="
	.byte	82
	.base64	"HhERHhQSEQ=="
	.byte	83
	.base64	"DxAQDgEBHg=="
	.byte	86
	.base64	"EREREREKBA=="
	.globl	FONT_SIZE
	.section	.srodata,"a"
	.align	2
	.type	FONT_SIZE, @object
	.size	FONT_SIZE, 4
FONT_SIZE:
	.word	7
	.text
	.align	2
	.globl	font_lookup
	.type	font_lookup, @function
font_lookup:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	mv	a5,a0
	sb	a5,-33(s0)
	sw	zero,-20(s0)
	j	.L2
.L5:
	lui	a5,%hi(FONT)
	addi	a4,a5,%lo(FONT)
	lw	a5,-20(s0)
	slli	a5,a5,3
	add	a5,a4,a5
	lbu	a5,0(a5)
	lbu	a4,-33(s0)
	bne	a4,a5,.L3
	lw	a5,-20(s0)
	slli	a4,a5,3
	lui	a5,%hi(FONT)
	addi	a5,a5,%lo(FONT)
	add	a5,a4,a5
	addi	a5,a5,1
	j	.L4
.L3:
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L2:
	li	a5,7
	lw	a4,-20(s0)
	blt	a4,a5,.L5
	lui	a5,%hi(FONT+1)
	addi	a5,a5,%lo(FONT+1)
.L4:
	mv	a0,a5
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	font_lookup, .-font_lookup
	.ident	"GCC: (GNU) 16.1.0"
	.section	.note.GNU-stack,"",@progbits
