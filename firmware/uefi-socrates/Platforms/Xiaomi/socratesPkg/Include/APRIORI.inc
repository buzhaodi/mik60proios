APRIORI DXE {
  INF MdeModulePkg/Core/Dxe/DxeMain.inf
  INF MdeModulePkg/Universal/PCD/Dxe/Pcd.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/EnvDxe/EnvDxe.inf
!endif

  INF MdeModulePkg/Universal/ReportStatusCodeRouter/RuntimeDxe/ReportStatusCodeRouterRuntimeDxe.inf
  INF MdeModulePkg/Universal/StatusCodeHandler/RuntimeDxe/StatusCodeHandlerRuntimeDxe.inf
  INF MdeModulePkg/Core/RuntimeDxe/RuntimeDxe.inf
  INF ArmPkg/Drivers/CpuDxe/CpuDxe.inf
  INF ArmPkg/Drivers/ArmGicDxe/ArmGicDxe.inf
  INF EmbeddedPkg/MetronomeDxe/MetronomeDxe.inf
  INF ArmPkg/Drivers/TimerDxe/TimerDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/SmemDxe/SmemDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/DALSYSDxe/DALSYSDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/HWIODxe/HWIODxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ChipInfoDxe/ChipInfoDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/PlatformInfoDxe/PlatformInfoDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ProjectInfoDxe/ProjectInfoDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/HALIOMMUDxe/HALIOMMUDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ULogDxe/ULogDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/IPCCDxe/IPCCDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/GLinkDxe/GLinkDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/CmdDbDxe/CmdDbDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/PwrUtilsDxe/PwrUtilsDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/NpaDxe/NpaDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/RpmhDxe/RpmhDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/VcsDxe/VcsDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ClockDxe/ClockDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ICBDxe/ICBDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ShmBridgeDxe/ShmBridgeDxeLA.inf
  INF Binaries/socrates/QcomPkg/Drivers/TzDxe/ScmDxeCompat.inf
  INF Binaries/socrates/QcomPkg/Drivers/TLMMDxe/TLMMDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/I2CDxe/I2CDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/SPMIDxe/SPMIDxe.inf
!endif

  INF MdeModulePkg/Universal/ResetSystemRuntimeDxe/ResetSystemRuntimeDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/PmicDxe/PmicDxeLa.inf
!endif

  INF MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf
  INF MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf
  INF MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/SdccDxe/SdccDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UFSDxe/UFSDxe.inf
!endif

  INF FatPkg/EnhancedFatDxe/Fat.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/TzDxe/TzDxeLA.inf
!endif

  INF MdeModulePkg/Universal/Variable/RuntimeDxe/VariableRuntimeDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/DDRInfoDxe/DDRInfoDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/FeatureEnablerDxe/FeatureEnablerDxe.inf
!endif
!if $(USE_CUSTOM_DISPLAY_DRIVER) == 1
  INF socratesPkg/Drivers/SocratesGopLogDxe/SocratesGopLogDxe.inf
  INF socratesPkg/Drivers/SocratesDisplayDepexDxe/SocratesDisplayDepexDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/DisplayDxe/DisplayDxe.inf
!else
  INF SiliciumPkg/Drivers/SimpleFbDxe/SimpleFbDxe.inf
!endif
!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/PILProxyDxe/PILProxyDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/PILDxe/PILDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/SPSSDxe/SPSSDxe.inf
!endif

  INF MdeModulePkg/Universal/WatchdogTimerDxe/WatchdogTimer.inf
  INF MdeModulePkg/Universal/SecurityStubDxe/SecurityStubDxe.inf
  INF EmbeddedPkg/EmbeddedMonotonicCounter/EmbeddedMonotonicCounter.inf
  INF EmbeddedPkg/RealTimeClockRuntimeDxe/RealTimeClockRuntimeDxe.inf
  INF MdeModulePkg/Universal/PrintDxe/PrintDxe.inf
!if $(SOCRATES_VENDOR_HW) == 1
  # The stock device path driver comes from the vendor binaries, which this repository does
  # not carry (Binaries/ is the shared Device-Binaries submodule without socrates content).
  INF Binaries/socrates/MdeModulePkg/Universal/DevicePathDxe/DevicePathDxe.inf
!else
  # VENDOR_HW = 0 (first boot): the upstream driver, as Include/DXE.inc already lists it.
  INF MdeModulePkg/Universal/DevicePathDxe/DevicePathDxe.inf
!endif
  INF MdeModulePkg/Universal/CapsuleRuntimeDxe/CapsuleRuntimeDxe.inf
  INF MdeModulePkg/Universal/HiiDatabaseDxe/HiiDatabaseDxe.inf
  INF MdeModulePkg/Universal/BdsDxe/BdsDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/SPIDxe/SPIDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/PmicGlinkDxe/PmicGlinkDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UsbPwrCtrlDxe/UsbPwrCtrlDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/QcomChargerDxe/QcomChargerDxeLA.inf
  INF Binaries/socrates/QcomPkg/Drivers/ChargerExDxe/ChargerExDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UsbfnDwc3Dxe/UsbfnDwc3Dxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/XhciPciEmulationDxe/XhciPciEmulationDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/XhciDxe/XhciDxe.inf
!endif

  INF MdeModulePkg/Bus/Usb/UsbBusDxe/UsbBusDxe.inf
  INF MdeModulePkg/Bus/Usb/UsbKbDxe/UsbKbDxe.inf
  INF MdeModulePkg/Bus/Usb/UsbMassStorageDxe/UsbMassStorageDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/UsbMsdDxe/UsbMsdDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UsbDeviceDxe/UsbDeviceDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UsbConfigDxe/UsbConfigDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/TsensDxe/TsensDxe.inf

  # Headless until stock Socrates framebuffer data is available.

  INF Binaries/socrates/QcomPkg/Drivers/LimitsDxe/LimitsDxe.inf
  # Headless until stock Socrates framebuffer data is available.
  INF Binaries/socrates/QcomPkg/Drivers/GpiDxe/GpiDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/UCDxe/UCDxe.inf
  INF Binaries/socrates/QcomPkg/Drivers/RNGDxe/RngDxe.inf
!endif

  INF EmbeddedPkg/SimpleTextInOutSerial/SimpleTextInOutSerial.inf
  INF MdeModulePkg/Universal/Console/ConPlatformDxe/ConPlatformDxe.inf
  INF MdeModulePkg/Universal/Console/ConSplitterDxe/ConSplitterDxe.inf
  INF MdeModulePkg/Universal/Console/GraphicsConsoleDxe/GraphicsConsoleDxe.inf

!if $(SOCRATES_VENDOR_HW) == 1
  INF Binaries/socrates/QcomPkg/Drivers/RscDxe/RscDxe.inf
!endif
}
