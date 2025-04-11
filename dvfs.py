import subprocess
import re
import time
import sys
import os

def log(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    print(f"[{timestamp}] {message}")

def get_powermetrics_data():
    try:
        process = subprocess.Popen(['sudo', 'powermetrics', '--samplers', 'cpu_power,gpu_power,ane_power', '-i', '1', '-n', '1'],
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE)
        stdout, stderr = process.communicate(timeout=15)
        if process.returncode == 0:
            return stdout.decode('utf-8')
    except FileNotFoundError:
        log("错误: 本程序为macOS设计，无法在其他系统上运行")
        return None
    except subprocess.TimeoutExpired:
        log("错误: powermetrics 命令执行超时。请确保您已正确输入 sudo 密码。")
        return None

def parse_powermetrics_frequencies(output):
    frequencies = {"e_core": [], "p_core": [], "gpu": []}

    e_cluster_match = re.search(r"E(?:-\w+|\d+)?-Cluster HW active residency:.*?\(.*?\)", output, re.DOTALL)
    if e_cluster_match:
        e_cluster_line = e_cluster_match.group(0)
        e_freq_matches = re.findall(r"(\d+) MHz:", e_cluster_line)
        frequencies["e_core"].extend(sorted(list(set(int(freq) for freq in e_freq_matches))))

    p_cluster_matches = re.findall(r"P(?:-\w+|\d+)?-Cluster HW active residency:.*?\((.*?)\)", output, re.DOTALL)
    for p_cluster_freq_group in p_cluster_matches:
        p_freq_matches = re.findall(r"(\d+) MHz:", p_cluster_freq_group)
        frequencies["p_core"].extend([int(freq) for freq in p_freq_matches])
    frequencies["p_core"] = sorted(list(set(frequencies["p_core"])))

    gpu_match = re.search(r"GPU HW active residency:.*?\(.*?\)", output, re.DOTALL)
    if gpu_match:
        gpu_line = gpu_match.group(0)
        gpu_freq_matches = re.findall(r"(\d+) MHz:", gpu_line)
        frequencies["gpu"].extend(sorted(list(set(int(freq) for freq in gpu_freq_matches))))

    return frequencies

def parse_socpowerbud_voltages(output_buffer):
    voltages = {"e_core": {}, "p_core": {}, "gpu": {}}

    pcpu_match = re.search(r"(\d+)-Core PCPU.*?DVFS distribution:\n(.*?)(?:\n\d+-Core ECPU|\nIntegrated Graphics|$)", output_buffer, re.DOTALL)
    if pcpu_match:
        dvfs_info = pcpu_match.group(2)
        freq_volt_matches = re.findall(r"(\d+) MHz \((\d+) mv\):.*?", dvfs_info)
        for freq, volt in freq_volt_matches:
            voltages["p_core"][int(freq)] = int(volt)

    ecpu_match = re.search(r"(\d+)-Core ECPU.*?DVFS distribution:\n(.*?)(?:\n\d+-Core PCPU|\nIntegrated Graphics|$)", output_buffer, re.DOTALL)
    if ecpu_match:
        dvfs_info = ecpu_match.group(2)
        freq_volt_matches = re.findall(r"(\d+) MHz \((\d+) mv\):.*?", dvfs_info)
        for freq, volt in freq_volt_matches:
            voltages["e_core"][int(freq)] = int(volt)

    gpu_match = re.search(r"Integrated Graphics.*?DVFS distribution:\n(.*?)(?:\n\d+-Core|$)", output_buffer, re.DOTALL)
    if gpu_match:
        dvfs_info = gpu_match.group(1)
        freq_volt_matches = re.findall(r"\s*(\d+) MHz \((\d+) mv\): (\d+\.\d+)%", dvfs_info)
        for freq, volt, _ in freq_volt_matches:
            voltages["gpu"][int(freq)] = int(volt)

    return voltages

if __name__ == "__main__":
    print("自动电压检测工具V0.0.8 By Celestial紗雪")
    powermetrics_output = get_powermetrics_data()
    if powermetrics_output:
        frequencies = parse_powermetrics_frequencies(powermetrics_output)
        print("检测到的 CPU/GPU 频率档位:")
        print("  E-core:", frequencies["e_core"])
        print("  P-core:", frequencies["p_core"])
        print("  GPU:", frequencies["gpu"])

        socpowerbud_process = None
        e_core_voltages = {}
        p_core_voltages = {}
        gpu_voltages = {}
        current_buffer = ""
        cpu_model = "N/A"
        supported_models = r"Apple M[1-3] (Pro|Max|Ultra|)" # 匹配 M1, M2, M3 及其 Pro/Max/Ultra 版本

        try:
            socpowerbud_process = subprocess.Popen(['./socpowerbud', '-a', '-s', '0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=1, universal_newlines=True)
            print("\n--- 实时读取 socpowerbud 数据 (Ctrl+C 停止) ---")

            # 读取一行来获取 CPU 型号
            model_line = socpowerbud_process.stdout.readline().strip()
            model_match = re.match(r"Profiling (.*?)\.\.\.", model_line)
            if model_match:
                cpu_model = model_match.group(1)
                print(f"CPU 型号: {cpu_model}")
                if not re.match(supported_models, cpu_model):
                    print(f"不支持的 CPU 型号: {cpu_model}。停止执行。")
                    socpowerbud_process.terminate()
                    socpowerbud_process.wait()
                    sys.exit(1)

            while True:
                line = socpowerbud_process.stdout.readline()
                current_buffer += line

                if re.match(r"\d+-Core PCPU$", line): # 精确匹配不带数字的 PCPU 行
                    # 当检测到新的 PCPU 循环开始时，尝试解析之前的数据
                    if "Integrated Graphics" in current_buffer and re.search(r"\d+-Core ECPU", current_buffer):
                        voltages = parse_socpowerbud_voltages(current_buffer)

                        if voltages["e_core"]:
                            e_core_voltages.update(voltages["e_core"])
                        if voltages["p_core"]:
                            p_core_voltages.update(voltages["p_core"])
                        if voltages["gpu"]:
                            gpu_voltages.update(voltages["gpu"])
                        os.system('cls' if os.name == 'nt' else 'clear')
                        print(f"CPU 型号: {cpu_model}")
                        print("\n--- 电压数据 ---")
                        e_core_output = "  E-core:\n"
                        print("  E-core:")
                        for freq in frequencies["e_core"]:
                            output_line = f"    {freq} MHz: {e_core_voltages.get(freq, 'N/A')} mV\n"
                            print(output_line, end='')
                            e_core_output += output_line

                        p_core_output = "  P-core:\n"
                        print("  P-core:")
                        for freq in frequencies["p_core"]:
                            output_line = f"    {freq} MHz: {p_core_voltages.get(freq, 'N/A')} mV\n"
                            print(output_line, end='')
                            p_core_output += output_line

                        gpu_output = "  GPU:\n"
                        print("  GPU:")
                        for freq_pm in frequencies["gpu"]:
                            found = False
                            for freq_sb, volt in gpu_voltages.items():
                                if abs(freq_pm - freq_sb) <= 1:
                                    output_line = f"    {freq_pm} MHz: {volt} mV (socpowerbud: {freq_sb} MHz)\n"
                                    print(output_line, end='')
                                    gpu_output += output_line
                                    found = True
                                    break
                            if not found:
                                output_line = f"    {freq_pm} MHz: N/A mV\n"
                                print(output_line, end='')
                                gpu_output += output_line

                        # 写入到文本文件 (覆盖模式)
                        with open("voltage_log.txt", "w") as f:
                            f.write(f"CPU 型号: {cpu_model}\n")
                            f.write("\n--- 电压数据 ---\n")
                            f.write(e_core_output)
                            f.write(p_core_output)
                            f.write(gpu_output)

                        # 清空 buffer，开始收集新的数据块
                        current_buffer = line

        except KeyboardInterrupt:
            log("程序被用户中断。")
        except FileNotFoundError:
            log("错误: socpowerbud 命令未找到。请确保您在本程序的目录下执行。")
        finally:
            if socpowerbud_process:
                return_code = socpowerbud_process.poll()
                if return_code is None:
                    socpowerbud_process.terminate()
                    socpowerbud_process.wait()
