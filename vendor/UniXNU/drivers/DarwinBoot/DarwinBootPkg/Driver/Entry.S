// SPDX-License-Identifier: BSD-2-Clause-Patent
#include <AsmMacroLib.h>

ASM_FUNC(DarwinCurrentEl)
  mrs x0, CurrentEL
  ret

// x0=boot_args PA, x1=entry PA, x2=owned PA, x3=owned size, x4=frame buffer
// PA (0 for none), x5=its size in bytes. EL1 only.
//
// Stage telemetry (diagnostic build): band 0 green = handoff entered, band 2
// yellow = window flush starting, band 3 cyan = flush done (before the I-cache
// invalidate and MMU off), band 4 white = about to branch to the kernel.
ASM_FUNC(DarwinEnter)
  msr daifset, #15
  mov x12, xzr
  mov x13, xzr
  // Paint the top 1/16 of the framebuffer green (BGRA 0xFF00FF00)
  // before cache maintenance, MMU shutdown and the branch to the kernel.
  cbz x4, 2f
  mov x12, x4
  mov x13, x5
  lsr x9, x5, #4
  bic x9, x9, #7
  mov w10, #0xFF00
  movk w10, #0xFF00, lsl #16
  mov x11, x4
3:
  stp w10, w10, [x11], #8
  subs x9, x9, #8
  b.hi 3b
  dsb sy
2:
  cbz x12, 5f
  // band 2 yellow: the dc civac walk over the window is about to start
  lsr x9, x13, #4
  bic x9, x9, #7
  mov w10, #0xFFFF
  movk w10, #0xFF00, lsl #16
  add x11, x12, x9, lsl #1
4:
  stp w10, w10, [x11], #8
  subs x9, x9, #8
  b.hi 4b
  dsb sy
5:
  add x5, x2, x3
  mrs x6, ctr_el0
  ubfx x6, x6, #16, #4
  mov x7, #4
  lsl x6, x7, x6
  sub x7, x6, #1
  bic x4, x2, x7
  dsb sy
1:
  dc civac, x4
  add x4, x4, x6
  cmp x4, x5
  b.lo 1b
  dsb sy
  cbz x12, 6f
  // band 3 cyan: window flush complete, I-cache invalidate / MMU off next
  lsr x9, x13, #4
  bic x9, x9, #7
  mov w10, #0xFF00
  movk w10, #0xFFFF, lsl #16
  add x11, x12, x9
  add x11, x11, x9, lsl #1
7:
  stp w10, w10, [x11], #8
  subs x9, x9, #8
  b.hi 7b
  dsb sy
6:
  ic iallu
  dsb sy
  isb
  mrs x4, sctlr_el1
  bic x4, x4, #1
  bic x4, x4, #4
  bic x4, x4, #0x1000
  msr sctlr_el1, x4
  isb
  tlbi vmalle1
  dsb sy
  isb
  cbz x12, 8f
  // band 4 white: branching to the kernel entry now
  lsr x9, x13, #4
  bic x9, x9, #7
  mov w10, #0xFFFF
  movk w10, #0xFFFF, lsl #16
  add x11, x12, x9, lsl #2
9:
  stp w10, w10, [x11], #8
  subs x9, x9, #8
  b.hi 9b
  dsb sy
8:
  br x1
