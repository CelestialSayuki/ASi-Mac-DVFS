# ASi-Mac-DVFS

Python script to profile full frequency, voltage on Apple Silicon.

- **Table of contents**
  - **[Project Deets](#project-deets)**
  - **[Example Output](#example-output)**
  - **[Features](#features)**
  - **[Future Stuff](#future-stuff)**
  - **[Usage](#usage)**
  - **[Compatibility Notes](#compatibility-notes)**
  - **[Contribution](#contribution)**
  - **[Credits](#credits)**

___

## Project Deets
This tool samples values from the `powermetrics` and `socpowerbud`, then returns formatted results for various metrics.  
`Socpowerbud` is to difficult to get all the data at once, so this tool merged them together.  
**If you dont want to run by yourself, move to [Discussions](https://github.com/CelestialSayuki/ASi-Mac-DVFS/discussions) to get the data.**

## Example Output
**Note:** The following is a complete output of `python3 dvfs.py` running on a M1 Max 14" Macbook Pro.
<details>

<summary>Expand Example to see...</summary>

```

自动电压检测工具V0.0.6 By Celestial紗雪
Password:
检测到的 CPU/GPU 频率档位:
  E-core: [600, 972, 1332, 1704, 2064]
  P-core: [600, 828, 1056, 1296, 1524, 1752, 1980, 2208, 2448, 2676, 2904, 3036, 3132, 3168, 3228]
  GPU: [389, 486, 648, 778, 972, 1296]

--- 实时读取 socpowerbud 数据 (Ctrl+C 停止) ---

CPU 型号: Apple M1 Max (T6001)

--- 电压数据 ---
  E-core:
    600 MHz: N/A mV
    972 MHz: 565 mV
    1332 MHz: 596 mV
    1704 MHz: 643 mV
    2064 MHz: 718 mV
  P-core:
    600 MHz: 768 mV
    828 MHz: 768 mV
    1056 MHz: 784 mV
    1296 MHz: 812 mV
    1524 MHz: 818 mV
    1752 MHz: 843 mV
    1980 MHz: 868 mV
    2208 MHz: 912 mV
    2448 MHz: 965 mV
    2676 MHz: 1025 mV
    2904 MHz: 1068 mV
    3036 MHz: 1068 mV
    3132 MHz: 1068 mV
    3168 MHz: 1068 mV
    3228 MHz: 1068 mV
  GPU:
    389 MHz: 612 mV (socpowerbud: 388 MHz)
    486 MHz: 640 mV (socpowerbud: 486 MHz)
    648 MHz: 671 mV (socpowerbud: 648 MHz)
    778 MHz: 709 mV (socpowerbud: 777 MHz)
    972 MHz: 765 mV (socpowerbud: 972 MHz)
    1296 MHz: 875 mV (socpowerbud: 1296 MHz)

```

</details>

## Features

The following metrics are available:
- Active Frequencies and Voltage
- DVFS Distribution 

## Future Stuff
- Support for M4 Macs.
- Sync with socpowerbud.

## Usage
**Note:** You need to `cd` to it's folder before running it. 

## Compatibility Notes
Incompatiable with M4 Macs.

## Contribution
If any bugs or issues are found, please let me know in the [issues](https://github.com/CelestialSayuki/ASi-Mac-DVFS/issues) section.

## Credits

- [dehydratedpotato](https://github.com/dehydratedpotato/) for [SocPowerBud](https://github.com/dehydratedpotato/socpowerbud)
