	.file	"gfx.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	set_palette
	.type	set_palette, @function
set_palette:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	mv	a5,a0
	mv	a4,a3
	sb	a5,-17(s0)
	mv	a5,a1
	sb	a5,-18(s0)
	mv	a5,a2
	sb	a5,-19(s0)
	mv	a5,a4
	sb	a5,-20(s0)
	lbu	a5,-18(s0)
	slli	a4,a5,16
	lbu	a5,-19(s0)
	slli	a5,a5,8
	or	a3,a4,a5
	lbu	a4,-20(s0)
	lbu	a5,-17(s0)
	slli	a2,a5,2
	li	a5,131072
	add	a5,a2,a5
	or	a4,a3,a4
	sw	a4,0(a5)
	nop
	lw	ra,28(sp)
	lw	s0,24(sp)
	addi	sp,sp,32
	jr	ra
	.size	set_palette, .-set_palette
	.align	2
	.globl	draw_pixel
	.type	draw_pixel, @function
draw_pixel:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	sw	a0,-20(s0)
	sw	a1,-24(s0)
	mv	a5,a2
	sb	a5,-25(s0)
	lw	a5,-20(s0)
	blt	a5,zero,.L6
	lw	a4,-20(s0)
	li	a5,319
	bgt	a4,a5,.L6
	lw	a5,-24(s0)
	blt	a5,zero,.L6
	lw	a4,-24(s0)
	li	a5,199
	bgt	a4,a5,.L6
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	slli	a5,a5,6
	mv	a4,a5
	lw	a5,-20(s0)
	add	a5,a4,a5
	mv	a4,a5
	li	a5,65536
	add	a5,a4,a5
	lbu	a4,-25(s0)
	sb	a4,0(a5)
	j	.L2
.L6:
	nop
.L2:
	lw	ra,28(sp)
	lw	s0,24(sp)
	addi	sp,sp,32
	jr	ra
	.size	draw_pixel, .-draw_pixel
	.align	2
	.globl	fill_rect
	.type	fill_rect, @function
fill_rect:
	addi	sp,sp,-64
	sw	ra,60(sp)
	sw	s0,56(sp)
	addi	s0,sp,64
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	a3,-48(s0)
	mv	a5,a4
	sb	a5,-49(s0)
	sw	zero,-20(s0)
	j	.L8
.L11:
	sw	zero,-24(s0)
	j	.L9
.L10:
	lw	a4,-36(s0)
	lw	a5,-24(s0)
	add	a3,a4,a5
	lw	a4,-40(s0)
	lw	a5,-20(s0)
	add	a5,a4,a5
	lbu	a4,-49(s0)
	mv	a2,a4
	mv	a1,a5
	mv	a0,a3
	call	draw_pixel
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L9:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L10
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L8:
	lw	a4,-20(s0)
	lw	a5,-48(s0)
	blt	a4,a5,.L11
	nop
	nop
	lw	ra,60(sp)
	lw	s0,56(sp)
	addi	sp,sp,64
	jr	ra
	.size	fill_rect, .-fill_rect
	.align	2
	.globl	draw_hline
	.type	draw_hline, @function
draw_hline:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	mv	a5,a3
	sb	a5,-45(s0)
	sw	zero,-20(s0)
	j	.L13
.L14:
	lw	a4,-36(s0)
	lw	a5,-20(s0)
	add	a5,a4,a5
	lbu	a4,-45(s0)
	mv	a2,a4
	lw	a1,-40(s0)
	mv	a0,a5
	call	draw_pixel
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L13:
	lw	a4,-20(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L14
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	draw_hline, .-draw_hline
	.align	2
	.globl	draw_vline
	.type	draw_vline, @function
draw_vline:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	mv	a5,a3
	sb	a5,-45(s0)
	sw	zero,-20(s0)
	j	.L16
.L17:
	lw	a4,-40(s0)
	lw	a5,-20(s0)
	add	a5,a4,a5
	lbu	a4,-45(s0)
	mv	a2,a4
	mv	a1,a5
	lw	a0,-36(s0)
	call	draw_pixel
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L16:
	lw	a4,-20(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L17
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	draw_vline, .-draw_vline
	.align	2
	.globl	draw_rect
	.type	draw_rect, @function
draw_rect:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-20(s0)
	sw	a1,-24(s0)
	sw	a2,-28(s0)
	sw	a3,-32(s0)
	mv	a5,a4
	sb	a5,-33(s0)
	lbu	a5,-33(s0)
	mv	a3,a5
	lw	a2,-28(s0)
	lw	a1,-24(s0)
	lw	a0,-20(s0)
	call	draw_hline
	lw	a4,-24(s0)
	lw	a5,-32(s0)
	add	a5,a4,a5
	addi	a5,a5,-1
	lbu	a4,-33(s0)
	mv	a3,a4
	lw	a2,-28(s0)
	mv	a1,a5
	lw	a0,-20(s0)
	call	draw_hline
	lbu	a5,-33(s0)
	mv	a3,a5
	lw	a2,-32(s0)
	lw	a1,-24(s0)
	lw	a0,-20(s0)
	call	draw_vline
	lw	a4,-20(s0)
	lw	a5,-28(s0)
	add	a5,a4,a5
	addi	a5,a5,-1
	lbu	a4,-33(s0)
	mv	a3,a4
	lw	a2,-32(s0)
	lw	a1,-24(s0)
	mv	a0,a5
	call	draw_vline
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	draw_rect, .-draw_rect
	.align	2
	.globl	clear_screen
	.type	clear_screen, @function
clear_screen:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	mv	a5,a0
	sb	a5,-17(s0)
	lbu	a5,-17(s0)
	mv	a4,a5
	li	a3,200
	li	a2,320
	li	a1,0
	li	a0,0
	call	fill_rect
	nop
	lw	ra,28(sp)
	lw	s0,24(sp)
	addi	sp,sp,32
	jr	ra
	.size	clear_screen, .-clear_screen
	.ident	"GCC: (GNU) 16.1.0"
	.section	.note.GNU-stack,"",@progbits
