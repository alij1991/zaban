import 'dart:io';
import '../models/hardware_tier.dart';

/// Detects available GPU hardware and recommends model tier.
class HardwareDetectionService {
  /// Detect VRAM and return recommended hardware tier.
  static Future<HardwareDetectionResult> detect() async {
    double? vramGb;
    String? gpuName;

    // Strategy 1: nvidia-smi (most reliable for NVIDIA GPUs, also works on
    // Linux and — on the rare eGPU macOS setup — via CUDA). Harmless on
    // systems where it doesn't exist; Process.run just throws and we catch.
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name,memory.total',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        if (output.isNotEmpty) {
          // Handle multi-GPU: pick the one with most VRAM
          for (final line in output.split('\n')) {
            final parts = line.split(',').map((s) => s.trim()).toList();
            if (parts.length >= 2) {
              final mb = double.tryParse(parts[1]);
              if (mb != null) {
                final gb = mb / 1024;
                if (vramGb == null || gb > vramGb) {
                  gpuName = parts[0];
                  vramGb = gb;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // Strategy 2: PowerShell with registry (avoids WMI's 4GB AdapterRAM overflow)
    // Windows-only — PowerShell + Get-CimInstance don't exist on macOS/Linux.
    if (vramGb == null && Platform.isWindows) {
      try {
        // Use qmem (dedicated video memory) via DirectX — more reliable than WMI
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r'''
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$name = $gpu.Name
# AdapterRAM overflows at 4GB (UInt32). Check registry for actual VRAM.
$regVram = $null
try {
  $regPath = 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
  $qmem = (Get-ItemProperty -Path $regPath -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
  if ($qmem) { $regVram = [math]::Round($qmem / 1GB, 1) }
} catch {}
if (-not $regVram) {
  $adapterRam = $gpu.AdapterRAM
  if ($adapterRam -and $adapterRam -gt 0) { $regVram = [math]::Round($adapterRam / 1GB, 1) }
}
"$name|$regVram"
''',
        ]).timeout(const Duration(seconds: 10));

        if (result.exitCode == 0) {
          final output = (result.stdout as String).trim();
          final parts = output.split('|');
          if (parts.length >= 2) {
            gpuName = parts[0].trim();
            vramGb = double.tryParse(parts[1].trim());
          }
        }
      } catch (_) {}
    }

    // Get system RAM — per-platform probe. LlmModelCatalog.pickForRam relies
    // on this, so falling back to null degrades to the smallest model.
    double? systemRamGb;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ]).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final bytes = int.tryParse((result.stdout as String).trim());
          if (bytes != null) {
            systemRamGb = bytes / (1024 * 1024 * 1024);
          }
        }
      } else if (Platform.isMacOS) {
        // `sysctl -n hw.memsize` → total physical memory in bytes.
        // Reliable on both Apple Silicon and Intel Macs.
        final result = await Process.run('sysctl', ['-n', 'hw.memsize'])
            .timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final bytes = int.tryParse((result.stdout as String).trim());
          if (bytes != null) {
            systemRamGb = bytes / (1024 * 1024 * 1024);
          }
        }
      } else if (Platform.isLinux) {
        // /proc/meminfo first line: "MemTotal:       16383440 kB"
        final meminfo = await File('/proc/meminfo').readAsString();
        final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(meminfo);
        if (match != null) {
          final kb = int.tryParse(match.group(1)!);
          if (kb != null) systemRamGb = kb / (1024 * 1024);
        }
      }
    } catch (_) {}

    final tier = vramGb != null
        ? HardwareTier.fromVram(vramGb)
        : HardwareTier.cpuOnly;

    return HardwareDetectionResult(
      tier: tier,
      gpuName: gpuName,
      vramGb: vramGb,
      systemRamGb: systemRamGb,
    );
  }
}

class HardwareDetectionResult {
  const HardwareDetectionResult({
    required this.tier,
    this.gpuName,
    this.vramGb,
    this.systemRamGb,
  });

  final HardwareTier tier;
  final String? gpuName;
  final double? vramGb;
  final double? systemRamGb;

  String get summary {
    final parts = <String>[];
    if (gpuName != null) parts.add(gpuName!);
    if (vramGb != null) parts.add('${vramGb!.toStringAsFixed(1)} GB VRAM');
    if (systemRamGb != null) {
      parts.add('${systemRamGb!.toStringAsFixed(0)} GB RAM');
    }
    if (parts.isEmpty) return 'Unknown hardware';
    return parts.join(' / ');
  }
}
