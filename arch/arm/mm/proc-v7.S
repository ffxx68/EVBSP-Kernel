/*
 *  linux/arch/arm/mm/proc-v7.S
 *
 *  Copyright (C) 2010 Renesas Electronics Corporation
 *  Copyright (C) 2001 Deep Blue Solutions Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 *  This is the "shell" of the ARMv7 processor support.
 */
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/asm-offsets.h>
#include <asm/hwcap.h>
#include <asm/pgtable-hwdef.h>
#include <asm/pgtable.h>

#ifdef CONFIG_ARCH_EMXX
#include <mach/scu.h>
#endif

#include "proc-macros.S"

#define TTB_C		(1 << 0)
#define TTB_S		(1 << 1)
#define TTB_RGN_NC	(0 << 3)
#define TTB_RGN_OC_WBWA	(1 << 3)
#define TTB_RGN_OC_WT	(2 << 3)
#define TTB_RGN_OC_WB	(3 << 3)
#define TTB_NOS		(1 << 5)
#define TTB_IRGN_NC	((0 << 0) | (0 << 6))
#define TTB_IRGN_WBWA	((0 << 0) | (1 << 6))
#define TTB_IRGN_WT	((1 << 0) | (0 << 6))
#define TTB_IRGN_WB	((1 << 0) | (1 << 6))

#ifndef CONFIG_SMP
#ifdef CONFIG_EMXX_L310_WT
/* PTWs cacheable, inner WB not shareable, outer WB not shareable */
#define TTB_FLAGS	TTB_IRGN_WB|TTB_RGN_OC_WT
#elif defined(CONFIG_EMXX_L310_NORAM)
/* PTWs cacheable, inner WB not shareable, outer non-cache not shareable */
#define TTB_FLAGS	TTB_IRGN_WB|TTB_RGN_NC
#else
/* PTWs cacheable, inner WB not shareable, outer WB not shareable */
#define TTB_FLAGS	TTB_IRGN_WB|TTB_RGN_OC_WB
#endif
#define PMD_SECT_SMP	0
#else
#ifdef CONFIG_EMXX_L310_WT
/* PTWs cacheable, inner WBWA shareable, outer WT not shareable */
#define TTB_FLAGS	TTB_IRGN_WBWA|TTB_S|TTB_NOS|TTB_RGN_OC_WT
#elif defined(CONFIG_EMXX_L310_NORAM)
/* PTWs cacheable, inner WBWA shareable, outer non-cache not shareable */
#define TTB_FLAGS	TTB_IRGN_WBWA|TTB_S|TTB_NOS|TTB_RGN_NC
#else
/* PTWs cacheable, inner WBWA shareable, outer WBWA not shareable */
#define TTB_FLAGS	TTB_IRGN_WBWA|TTB_S|TTB_NOS|TTB_RGN_OC_WBWA
#endif
#define PMD_SECT_SMP	PMD_SECT_S
#endif

ENTRY(cpu_v7_proc_init)
	mov	pc, lr
ENDPROC(cpu_v7_proc_init)

ENTRY(cpu_v7_proc_fin)
	mov	pc, lr
ENDPROC(cpu_v7_proc_fin)

/*
 *	cpu_v7_reset(loc)
 *
 *	Perform a soft reset of the system.  Put the CPU into the
 *	same state as it would be if it had been reset, and branch
 *	to what would be the reset vector.
 *
 *	- loc   - location to jump to for soft reset
 *
 *	It is assumed that:
 */
	.align	5
ENTRY(cpu_v7_reset)
	mov	pc, r0
ENDPROC(cpu_v7_reset)

/*
 *	cpu_v7_do_idle()
 *
 *	Idle the processor (eg, wait for interrupt).
 *
 *	IRQs are already disabled.
 */
#ifdef CONFIG_EMXX_L310
#include <mach/hardware.h>
#include <asm/hardware/cache-l2x0.h>
	.align	5
ENTRY(cpu_v7_do_idle)
	ldr	r2, =EMXX_L2CC_VIRT
	dsb

	mov	r0, #0x1
	str	r0, [r2, #L2X0_CACHE_SYNC]	@ L2 Sync
L2_sync_loop:
	ldr	r0, [r2, #L2X0_CACHE_SYNC]
	cmp	r0, #0
	bne	L2_sync_loop

	wfi
	mov	pc, lr
#else
ENTRY(cpu_v7_do_idle)
	dsb					@ WFI may enter a low-power mode
	wfi
	mov	pc, lr
#endif
ENDPROC(cpu_v7_do_idle)

ENTRY(cpu_v7_dcache_clean_area)
#ifndef TLB_CAN_READ_FROM_L1_CACHE
	dcache_line_size r2, r3
1:	mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
	add	r0, r0, r2
	subs	r1, r1, r2
	bhi	1b
	dsb
#endif
	mov	pc, lr
ENDPROC(cpu_v7_dcache_clean_area)

/*
 *	cpu_v7_switch_mm(pgd_phys, tsk)
 *
 *	Set the translation table base pointer to be pgd_phys
 *
 *	- pgd_phys - physical address of new TTB
 *
 *	It is assumed that:
 *	- we are not using split page tables
 */
ENTRY(cpu_v7_switch_mm)
#ifdef CONFIG_MMU
	mov	r2, #0
	ldr	r1, [r1, #MM_CONTEXT_ID]	@ get mm->context.id
	orr	r0, r0, #TTB_FLAGS
	mcr	p15, 0, r2, c13, c0, 1		@ set reserved context ID
	isb
1:	mcr	p15, 0, r0, c2, c0, 0		@ set TTB 0
	isb
	mcr	p15, 0, r1, c13, c0, 1		@ set context ID
	isb
#endif
	mov	pc, lr
ENDPROC(cpu_v7_switch_mm)

/*
 *	cpu_v7_set_pte_ext(ptep, pte)
 *
 *	Set a level 2 translation table entry.
 *
 *	- ptep  - pointer to level 2 translation table entry
 *		  (hardware version is stored at -1024 bytes)
 *	- pte   - PTE value to store
 *	- ext	- value for extended PTE bits
 */
ENTRY(cpu_v7_set_pte_ext)
#ifdef CONFIG_MMU
	str	r1, [r0], #-2048		@ linux version

	bic	r3, r1, #0x000003f0
	bic	r3, r3, #PTE_TYPE_MASK
	orr	r3, r3, r2
	orr	r3, r3, #PTE_EXT_AP0 | 2

	tst	r1, #1 << 4
	orrne	r3, r3, #PTE_EXT_TEX(1)

	tst	r1, #L_PTE_WRITE
	tstne	r1, #L_PTE_DIRTY
	orreq	r3, r3, #PTE_EXT_APX

	tst	r1, #L_PTE_USER
	orrne	r3, r3, #PTE_EXT_AP1
	tstne	r3, #PTE_EXT_APX
	bicne	r3, r3, #PTE_EXT_APX | PTE_EXT_AP0

	tst	r1, #L_PTE_EXEC
	orreq	r3, r3, #PTE_EXT_XN

	tst	r1, #L_PTE_YOUNG
	tstne	r1, #L_PTE_PRESENT
	moveq	r3, #0

	str	r3, [r0]
	mcr	p15, 0, r0, c7, c10, 1		@ flush_pte
#endif
	mov	pc, lr
ENDPROC(cpu_v7_set_pte_ext)

cpu_v7_name:
	.ascii	"ARMv7 Processor"
	.align

	.section ".text.init", #alloc, #execinstr

/*
 *	__v7_setup
 *
 *	Initialise TLB, Caches, and MMU state ready to switch the MMU
 *	on.  Return in r0 the new CP15 C1 control register setting.
 *
 *	We automatically detect if we have a Harvard cache, and use the
 *	Harvard cache control instructions insead of the unified cache
 *	control instructions.
 *
 *	This should be able to cover all ARMv7 cores.
 *
 *	It is assumed that:
 *	- cache type register is implemented
 */
__v7_setup:
#ifdef CONFIG_SMP
#ifdef CONFIG_ARCH_EMXX
	mrc	p15, 0, r0, c0, c0, 5		@ CPU core number
	ands	r0, r0, #15
	ldreq	r0, =SCU_BASE
	ldreq	r5, =0xffffffff
	streq	r5, [r0, #SCU_INVALIDATE]
	ldreq	r5, [r0, #SCU_CTRL]
	orreq	r5, r5, #1
	streq	r5, [r0, #SCU_CTRL]
#endif
	mrc	p15, 0, r0, c1, c0, 1		@ Enable SMP/nAMP mode
	tst	r0, #(0x1 << 6)			@ already enabled?
	itt	eq
	orreq	r0, r0, #(1 << 6) | (1 << 0)
	mcreq	p15, 0, r0, c1, c0, 1
#endif

#ifdef CONFIG_ARCH_EMXX
	mrc	p15, 0, r0, c1, c0, 1
	orr	r0, r0, #(1 << 2)		@ Enable L1 DPrefetch
	orr	r0, r0, #(1 << 1)		@ Enable L2 prefetch Hint
	mcr	p15, 0, r0, c1, c0, 1
#endif

#ifdef CONFIG_ARM_ERRATA_742230
	mrc	p15, 0, r0, c15, c0, 1
	orr	r0, r0, #0x10
	mcr	p15, 0, r0, c15, c0, 1
#endif
#ifdef CONFIG_ARM_ERRATA_743622
	mrc	p15, 0, r0, c15, c0, 1
	orr	r0, r0, #0x40
	mcr	p15, 0, r0, c15, c0, 1
#endif

	adr	r12, __v7_setup_stack		@ the local stack
	stmia	r12, {r0-r5, r7, r9, r11, lr}
	bl	v7_inv_dcache_all
	ldmia	r12, {r0-r5, r7, r9, r11, lr}
	mov	r10, #0
#ifdef HARVARD_CACHE
	mcr	p15, 0, r10, c7, c5, 0		@ I+BTB cache invalidate
#endif
	dsb
#ifdef CONFIG_MMU
	mcr	p15, 0, r10, c8, c7, 0		@ invalidate I + D TLBs
	mcr	p15, 0, r10, c2, c0, 2		@ TTB control register
	orr	r4, r4, #TTB_FLAGS
	mcr	p15, 0, r4, c2, c0, 1		@ load TTB1
	mov	r10, #0x1f			@ domains 0, 1 = manager
	mcr	p15, 0, r10, c3, c0, 0		@ load domain access register
	ldr	r5, =0xff0aa1a8
#ifdef CONFIG_EMXX_L310_WT
	ldr	r6, =0x80a040e0
#elif defined(CONFIG_EMXX_L310_NORAM)
	ldr	r6, =0x000040e0
#else
	ldr	r6, =0x40e040e0
#endif
	mcr	p15, 0, r5, c10, c2, 0		@ write PRRR
	mcr	p15, 0, r6, c10, c2, 1		@ write NMRR
#endif
	adr	r5, v7_crval
	ldmia	r5, {r5, r6}
   	mrc	p15, 0, r0, c1, c0, 0		@ read control register
	bic	r0, r0, r5			@ clear bits them
	orr	r0, r0, r6			@ set them
#ifdef CONFIG_ARM_ERRATA_716044
	orr	r0, r0, #(1 << 14)		@ set RR
#endif
	mov	pc, lr				@ return to head.S:__ret
ENDPROC(__v7_setup)

	/*   AT
	 *  TFR   EV X F   I D LR    S
	 * .EEE ..EE PUI. .T.T 4RVI ZWRS BLDP WCAM
	 * rxxx rrxx xxx0 0101 xxxx xxxx x111 xxxx < forced
	 *    1    0 110       0011 1100 .111 1101 < we want
	 */
	.type	v7_crval, #object
v7_crval:
	crval	clear=0x0120c302, mmuset=0x10c03c7d, ucset=0x00c01c7c

__v7_setup_stack:
	.space	4 * 11				@ 11 registers

	.type	v7_processor_functions, #object
ENTRY(v7_processor_functions)
	.word	v7_early_abort
	.word	pabort_ifar
	.word	cpu_v7_proc_init
	.word	cpu_v7_proc_fin
	.word	cpu_v7_reset
	.word	cpu_v7_do_idle
	.word	cpu_v7_dcache_clean_area
	.word	cpu_v7_switch_mm
	.word	cpu_v7_set_pte_ext
	.size	v7_processor_functions, . - v7_processor_functions

	.type	cpu_arch_name, #object
cpu_arch_name:
	.asciz	"armv7"
	.size	cpu_arch_name, . - cpu_arch_name

	.type	cpu_elf_name, #object
cpu_elf_name:
	.asciz	"v7"
	.size	cpu_elf_name, . - cpu_elf_name
	.align

	.section ".proc.info.init", #alloc, #execinstr

	/*
	 * Match any ARMv7 processor core.
	 */
	.type	__v7_proc_info, #object
__v7_proc_info:
	.long	0x000f0000		@ Required ID value
	.long	0x000f0000		@ Mask for ID
	.long   PMD_TYPE_SECT | \
		PMD_SECT_BUFFERABLE | \
		PMD_SECT_CACHEABLE | \
		PMD_SECT_AP_WRITE | \
		PMD_SECT_AP_READ | \
		PMD_SECT_SMP
	.long   PMD_TYPE_SECT | \
		PMD_SECT_XN | \
		PMD_SECT_AP_WRITE | \
		PMD_SECT_AP_READ
	b	__v7_setup
	.long	cpu_arch_name
	.long	cpu_elf_name
	.long	HWCAP_SWP|HWCAP_HALF|HWCAP_THUMB|HWCAP_FAST_MULT|HWCAP_EDSP
	.long	cpu_v7_name
	.long	v7_processor_functions
	.long	v7wbi_tlb_fns
	.long	v6_user_fns
	.long	v7_cache_fns
	.size	__v7_proc_info, . - __v7_proc_info
