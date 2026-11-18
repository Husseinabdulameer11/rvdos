	.file	"text_demo.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata
	.align	2
.LC0:
	.string	"RISC-V"
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	sw	s0,8(sp)
	addi	s0,sp,16
	li	a3,255
	li	a2,255
	li	a1,255
	li	a0,1
	call	set_palette
	li	a4,3
	li	a3,1
	lui	a5,%hi(.LC0)
	addi	a2,a5,%lo(.LC0)
	li	a1,20
	li	a0,20
	call	draw_string
	li	a5,0
	mv	a0,a5
	lw	ra,12(sp)
	lw	s0,8(sp)
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.ident	"GCC: (GNU) 16.1.0"
	.section	.note.GNU-stack,"",@progbits
