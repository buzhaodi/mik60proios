// SPDX-License-Identifier: BSD-3-Clause
// Memory map of the Redmi K60 Pro (socrates, SM8550).
//
// Every value below is measured from this phone's own stock firmware
// (socrates_images_OS3.0.304.0.WMKCNXM_20260713.0000.00_16.0_cn_cdb5f7269f.tgz):
//
//   * the stock uefiplat.cfg (the [MemoryMap]/[RegisterMap] text region of images/uefi.elf,
//     sha256 90648bc5b3aaffd3a509abe2c20121798826a9c27e8c39be3f90bd62366797ee, 8324 bytes)
//     supplies the UEFI allocations: FD window 0xA7000000 (4 MiB), stack 0xA760D000,
//     Display Reserved 0xB8000000+0x2B00000, DXE Heap, TZApps, the register map below 4 GiB;
//   * the socrates base dtb (the Kalama QCM blob of the stock vendor_boot.img, msm-id 0x25c)
//     supplies the fixed no-map reservations (PIL sub-regions, mpss, cdsp, adspslpi, qtee,
//     hwfence, llcc_lpi). Two name/reg mismatches are preserved as-is: mpss_region@89800000
//     carries reg 0x8A800000/0x10800000 and cvp_region@9c200000 carries reg 0x9CB00000;
//   * the socrates dtbo overlay entry 50 (model "8550 socrates", xiaomi,miboard-id 4) supplies
//     the board reservations (xbl_dt_log, aop_image, xbl_ramdump, dump_display@a4a80000); its
//     splash_region and disp_rdump_region sit inside the stock Display Reserved window, so
//     the single stock entry covers them.
//
// The port FD policy follows sheng/vermeer: a 3 MiB FD at 0xA7100000 inside the stock 4 MiB
// window at 0xA7000000, with the preceding 1 MiB kept reserved.
//
// The trust_ui/oem_vm gunyah regions (0xF3800000..0xFC000000) lie inside the conventional
// gap 0xE671D000..0xFF800000: UEFI runs before those VMs start, as on the sheng/vermeer maps.
// Nothing here is hardware validated on the K60 Pro yet.
#include <Library/MemoryMapLib.h>

STATIC EFI_MEMORY_REGION_DESCRIPTOR gMemoryDescriptor[] = {
  {"gunyah_hyp_region@80000000", 0x80000000, 0xa00000, HobOnlyNoCacheSetting, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"cpusys_vm_region@80a00000", 0x80a00000, 0x400000, HobOnlyNoCacheSetting, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"NOMAP", 0x80e00000, 0x400000, HobOnlyNoCacheSetting, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"xbl_ramdump_region@81200000", 0x81200000, 0x280000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"RSRV0", 0x81480000, 0x580000, AddMem, SYS_MEM, SYS_MEM_CAP, Reserv, WRITE_BACK_XN},
  {"xbl_dt_log@81a00000", 0x81a00000, 0x40000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"XBL Ramdump", 0x81a40000, 0x1c0000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"aop_image_region@81c00000", 0x81c00000, 0x60000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"aop_cmd_db_region@81c60000", 0x81c60000, 0x20000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"aop_config_merged_region", 0x81c80000, 0x74000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0x81cf4000", 0x81cf4000, 0xc000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"smem_region@81d00000", 0x81d00000, 0x200000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"adsp_mhi_region@81f00000", 0x81f00000, 0x20000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0x81f20000", 0x81f20000, 0x6e0000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"global_sync_region@82600000", 0x82600000, 0x100000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"tz_stat_region@82700000", 0x82700000, 0x100000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0x82800000", 0x82800000, 0x4600000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"RSRV1", 0x86e00000, 0x2a00000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_BACK_XN},
  {"DRAM gap 0x89800000", 0x89800000, 0x1000000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"mpss_region@89800000", 0x8a800000, 0x10800000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"q6_mpss_dtb_region@9b000000", 0x9b000000, 0x80000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"ipa_fw_region@9b080000", 0x9b080000, 0x10000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"ipa_gsi_region@9b090000", 0x9b090000, 0xa000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"gpu_micro_code_region@9b09a000", 0x9b09a000, 0x2000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"PIL Reserved", 0x9b09c000, 0x64000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"spss_region_region@9b100000", 0x9b100000, 0x180000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"spu_tz_shared_mem@9b280000", 0x9b280000, 0x60000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"spu_modem_shared_mem@9b2e0000", 0x9b2e0000, 0x20000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"camera_region@9b300000", 0x9b300000, 0x800000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"video_region@9bb00000", 0x9bb00000, 0x1000000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"cvp_region@9c200000", 0x9cb00000, 0x700000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"cdsp_region@9c900000", 0x9d200000, 0x2000000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"q6_cdsp_dtb_region@9e900000", 0x9f200000, 0x80000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"q6_adsp_dtb_region@9e980000", 0x9f280000, 0x80000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"adspslpi_region@9ea00000", 0x9f300000, 0x4080000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"Display Demura", 0xa3380000, 0x1700000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH_XN},
  {"dump_display_region@a4a80000", 0xa4a80000, 0x1000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"Display Demura", 0xa4a81000, 0xaff000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH_XN},
  {"DRAM gap 0xa5580000", 0xa5580000, 0xb80000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"DBI Dump", 0xa6100000, 0xf00000, AddMem, MMAP_IO, INITIALIZED, Conv, UNCACHED_UNBUFFERED_XN},
  {"FD Reserved", 0xa7000000, 0x100000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"UEFI FD", 0xa7100000, 0x300000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"UEFI FD Reserved", 0xa7400000, 0x200000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"CPU Vectors", 0xa7600000, 0x1000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"Info Blk", 0xa7601000, 0x1000, AddMem, SYS_MEM, SYS_MEM_CAP, RtData, WRITE_BACK_XN},
  {"MMU PageTables", 0xa7602000, 0x3000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"Log Buffer", 0xa7605000, 0x8000, AddMem, SYS_MEM, SYS_MEM_CAP, RtData, WRITE_BACK_XN},
  {"UEFI Stack", 0xa760d000, 0x40000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"SEC Heap", 0xa764d000, 0x8c000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"Sched Heap", 0xa76d9000, 0x400000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"FV Region", 0xa7ad9000, 0x400000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"UEFI RESV", 0xa7ed9000, 0x127000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN},
  {"Kernel", 0xa8000000, 0x10000000, AddMem, SYS_MEM, SYS_MEM_CAP, Reserv, WRITE_BACK_XN},
  {"Display Reserved", 0xb8000000, 0x2b00000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH_XN},
  {"DXE Heap", 0xbab00000, 0xd1c0000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"DRAM gap 0xc7cc0000", 0xc7cc0000, 0xd040000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"mpss_dsm_region@d4d00000", 0xd4d00000, 0x3300000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0xd8000000", 0xd8000000, 0x100000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"xbl_sc_region@d8100000", 0xd8100000, 0x40000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"cpucp_fw_region@d8140000", 0xd8140000, 0x1c0000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"qtee_region@d8300000", 0xd8300000, 0x500000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"TZApps Reserved", 0xd8800000, 0x7400000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0xdfc00000", 0xdfc00000, 0x6840000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"hwfence-shmem", 0xe6440000, 0x2dd000, AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM gap 0xe671d000", 0xe671d000, 0x190e3000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"llcc_lpi_region@ff800000", 0xff800000, 0x600000, HobOnlyNoCacheSetting, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"NOMAP", 0xffe00000, 0x200000, HobOnlyNoCacheSetting, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN},
  {"DRAM bank 1 low", 0x880000000, 0x3b300000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK_XN},
  {"IMEM Base", 0x14680000, 0x2a000, NoHob, MMAP_IO, INITIALIZED, Conv, NS_DEVICE},
  {"IMEM Cookie Base", 0x146aa000, 0x16000, AddDev, MMAP_IO, INITIALIZED, Conv, NS_DEVICE},
  {"IPC_ROUTER_TOP", 0x400000, 0x100000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"SECURITY CONTROL", 0x780000, 0x7000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"QUP", 0x800000, 0x300000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"PRNG_CFG_PRNG", 0x10c0000, 0xc000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"CRYPTO0 CRYPTO", 0x1dc0000, 0x40000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"CORE_TOP_CSR", 0x1f00000, 0x100000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"PERIPH_SS", 0x8800000, 0x100000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"USB", 0xa600000, 0x200000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"AOSS", 0xb000000, 0x4000000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"TLMM", 0xf000000, 0x1000000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"SMMU", 0x15000000, 0x200000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
  {"APSS_HM", 0x17000000, 0x2000000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, NS_DEVICE},
};

VOID
GetMemoryMap (
  OUT EFI_MEMORY_REGION_DESCRIPTOR **MemoryDescriptor,
  OUT UINT8                         *MemoryDescriptorCount)
{
  // Pass Data
  *MemoryDescriptor      = gMemoryDescriptor;
  *MemoryDescriptorCount = ARRAY_SIZE (gMemoryDescriptor);
}
