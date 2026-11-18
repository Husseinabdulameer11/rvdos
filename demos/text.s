	.file	"text.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	draw_char
	.type	draw_char, @function
draw_char:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	mv	a5,a2
	sw	a4,-48(s0)
	sb	a5,-41(s0)
	mv	a5,a3
	sb	a5,-42(s0)
	lbu	a5,-41(s0)
	mv	a0,a5
	call	font_lookup
	sw	a0,-28(s0)
	sw	zero,-20(s0)
	j	.L2
.L6:
	lw	a5,-20(s0)
	lw	a4,-28(s0)
	add	a5,a4,a5
	lbu	a5,0(a5)
	sb	a5,-29(s0)
	sw	zero,-24(s0)
	j	.L3
.L5:
	lbu	a4,-29(s0)
	li	a3,4
	lw	a5,-24(s0)
	sub	a5,a3,a5
	sra	a5,a4,a5
	andi	a5,a5,1
	beq	a5,zero,.L4
	lw	a4,-24(s0)
	lw	a5,-48(s0)
	mul	a4,a4,a5
	lw	a5,-36(s0)
	add	a0,a4,a5
	lw	a4,-20(s0)
	lw	a5,-48(s0)
	mul	a4,a4,a5
	lw	a5,-40(s0)
	add	a5,a4,a5
	lbu	a4,-42(s0)
	lw	a3,-48(s0)
	lw	a2,-48(s0)
	mv	a1,a5
	call	fill_rect
.L4:
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L3:
	lw	a4,-24(s0)
	li	a5,4
	ble	a4,a5,.L5
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L2:
	lw	a4,-20(s0)
	li	a5,6
	ble	a4,a5,.L6
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	draw_char, .-draw_char
	.align	2
	.globl	draw_string
	.type	draw_string, @function
draw_string:
	addi	sp,sp,-64
	sw	ra,60(sp)
	sw	s0,56(sp)
	addi	s0,sp,64
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	mv	a5,a3
	sw	a4,-52(s0)
	sb	a5,-45(s0)
	lw	a5,-36(s0)
	sw	a5,-20(s0)
	j	.L8
.L9:
	lw	a5,-44(s0)
	lbu	a5,0(a5)
	lbu	a3,-45(s0)
	lw	a4,-52(s0)
	mv	a2,a5
	lw	a1,-40(s0)
	lw	a0,-20(s0)
	call	draw_char
	lw	a4,-52(s0)
	mv	a5,a4
	slli	a5,a5,1
	add	a5,a5,a4
	slli	a5,a5,1
	mv	a4,a5
	lw	a5,-20(s0)
	add	a5,a5,a4
	sw	a5,-20(s0)
	lw	a5,-44(s0)
	addi	a5,a5,1
	sw	a5,-44(s0)
.L8:
	lw	a5,-44(s0)
	lbu	a5,0(a5)
	bne	a5,zero,.L9
	nop
	nop
	lw	ra,60(sp)
	lw	s0,56(sp)
	addi	sp,sp,64
	jr	ra
	.size	draw_string, .-draw_string
	.ident	"GCC: (GNU) 16.1.0"
	.section	.note.GNU-stack,"",@progbits
