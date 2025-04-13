# ASi-Mac-DVFS

A sudoless utility to profile frequency and voltage on Apple Silicon.

- **Table of contents**
  - **[Project Deets](#project-deets)**
  - **[Example Output](#example-output)**
  - **[Future Stuff](#future-stuff)**
  - **[Compatibility Notes](#compatibility-notes)**
  - **[Contribution](#contribution)**
  - **[Credits](#credits)**

___

## Project Deets
This tool gets inspiration from `socpowerbud`.  
`Socpowerbud` is unable to get ANE data and contains many functions I don't need. So I wrote this tool.  
**If you dont want to run by yourself, move to [Discussions](https://github.com/CelestialSayuki/ASi-Mac-DVFS/discussions) to get the data.**

## Example Output
**Note:** The following is a complete output running on a M1 Max 14" Macbook Pro.
<details>

<summary>Expand Example to see...</summary>

```

电压检测工具V0.0.8 By Celestial紗雪
CPU 型号: Apple M1 Max (T6001)

--- 电压数据 ---
E-core:
600 MHz: 565 mV
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
388 MHz: 612 mV
486 MHz: 640 mV
648 MHz: 671 mV
777 MHz: 709 mV
972 MHz: 765 mV
1296 MHz: 875 mV
ANE:
300 MHz: 562 mV
540 MHz: 618 mV
780 MHz: 650 mV
1020 MHz: 731 mV
1260 MHz: 793 mV
1500 MHz: 878 mV
```

</details>

## Future Stuff
- Support for M4 Macs.

## Compatibility Notes
Incompatiable with M4 Macs? I'm not sure.

## Contribution
If any bugs or issues are found, please let me know in the [issues](https://github.com/CelestialSayuki/ASi-Mac-DVFS/issues) section.

## Credits
- [dehydratedpotato](https://github.com/dehydratedpotato/) for [SocPowerBud](https://github.com/dehydratedpotato/socpowerbud)
