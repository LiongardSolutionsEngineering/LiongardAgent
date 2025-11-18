# Liongard Agent Deployment Guide (The Smart Installer)

## 🦁 Why Use These Scripts? (Working Smarter)

These scripts were built by the Liongard Solutions Engineering team to simplify and strengthen the process of installing and removing the Liongard Agent. They are more reliable than a standard installation because they include:

* **Intelligent Mode:** They automatically know if a person is running the script (Interactive Mode) or if an automation tool (RMM/Silent Mode) is running it.
* **Deep Troubleshooting:** If the installation fails, the script analyzes the error code and tells you exactly what went wrong (e.g., "The Access Key is incorrect" instead of just "Error 1603").
* **Clean Uninstallation:** The uninstaller is thorough, stopping the service, cleaning the registry, and removing leftover files safely.
* **Auto-Correction:** It fixes common mistakes, like if you forget to type `https://` or include `.app.liongard.com` in your URL.

---

## 🛠️ Repository Contents

We have three main scripts for Agent management:

| Script File Name | What It Does | Best Use Case |
| :--- | :--- | :--- |
| `InstallLiongardAgentPersistent2025.ps1` | **Installs the Agent.** The main script for new deployments. | New onboarding or deployment to a fresh server/workstation. |
| `UninstallLiongardAgent2025.ps1` | **Removes the Agent.** Safely and completely uninstalls the agent. | Offboarding, decommissioning a machine, or prior to a major server OS upgrade. |
| `UninstallReinstallLiongardAgent2025.ps1` | **Removes and Reinstalls.** Perfect for repairing a broken agent or performing an upgrade where you need fresh credentials. | Troubleshooting, tech evaluations, or bulk re-deployments. |

---

## ✅ Prerequisites (What You Need)

Before running any deployment, you must get these items from your Liongard instance:

* **Instance URL:** The address you log in to (e.g., `yourdomain.app.liongard.com`).
* **Access Key ID**
* **Access Key Secret**

These keys are generated in **Admin > Account > API Tokens** in your Liongard instance.

---

## 💻 Part 1: Installing Manually (The Human Way)

Use this method when you are sitting directly at the server or working on a single machine.

### Option A: The "Double-Click" Method

1.  Download the **`InstallLiongardAgentPersistent2025.ps1`** script to the target machine.
2.  **Right-click** the file and choose **Run with PowerShell**.
3.  The script will start and **ask you** for the required information (URL, Key, Secret).

### Option B: The "One-Liner" Method

If you want to run everything in one go, open **PowerShell as Administrator** and use the following command, replacing the highlighted placeholders with your actual details:

```powershell
.\InstallLiongardAgentPersistent2025.ps1 -Url "yourdomain.app.liongard.com" -AccessKey "YOUR_KEY" -AccessSecret "YOUR_SECRET" -Environment "Manual_Install"
````

-----

## 🤖 Part 2: Installing via RMM (The Smart Way)

This is how you scale deployment. When the script runs via an RMM (Remote Monitoring and Management tool), it runs **silently** and uses the credentials you pass to it from the RMM console.

### 1\. Datto RMM (Comodo)

| RMM Action | Value / Instructions |
| :--- | :--- |
| **Component Type** | Script (PowerShell) |
| **Input Variables** | Create RMM variables for: `LiongardUrl`, `AccessKey`, `AccessSecret` (set this to a **Password/Masked** type), and `Environment`. |
| **Execution Command** | Use the RMM's internal variables (`$env:`) to pass the data: |

```powershell
powershell.exe -ExecutionPolicy Bypass -File "InstallLiongardAgentPersistent2025.ps1" -Url "$env:LiongardUrl" -AccessKey "$env:AccessKey" -AccessSecret "$env:AccessSecret" -Environment "$env:Environment"
```

### 2\. ConnectWise Automate (CWA)

| RMM Action | Value / Instructions |
| :--- | :--- |
| **Script Function** | Execute Script -\> PowerShell |
| **Arguments (Parameters)** | Map your Liongard details directly to the script arguments. Use the CWA variable `%ClientName%` to automatically set the environment name to the client's name: |

```text
-Url "yourdomain.app.liongard.com" -AccessKey "YOUR_KEY" -AccessSecret "YOUR_SECRET" -Environment "%ClientName%"
```

### 3\. NinjaOne (Ninja RMM)

| RMM Action | Value / Instructions |
| :--- | :--- |
| **Script Settings** | Select PowerShell as the script type. |
| **Parameters** | Use the NinjaOne system variable `$msg.organization_name` to easily name the environment: |

```powershell
-Url "yourdomain.app.liongard.com" -AccessKey "YOUR_KEY" -AccessSecret "YOUR_SECRET" -Environment "$msg.organization_name"
```

### 4\. Kaseya VSA

| RMM Action | Value / Instructions |
| :--- | :--- |
| **Step 1: File Transfer** | Use the `writeFile` command to save the script to the agent's temp folder (`#vAgentConfiguration.agentTempDir#\LiongardInstall.ps1`). |
| **Step 2: Execution** | Use `executeShellCommand` to run the script from the temp folder: |

```powershell
powershell.exe -ExecutionPolicy Bypass -File "#vAgentConfiguration.agentTempDir#\LiongardInstall.ps1" -Url "yourdomain.app.liongard.com" -AccessKey "YOUR_KEY" -AccessSecret "YOUR_SECRET"
```

-----

## 🛑 Troubleshooting (Where to Look)

The scripts are designed to give you a clear error in the RMM or console output. If you need more detail, always check the local machine in the `C:\ProgramData\Liongard\` folder.

| File Path | What It Contains | Why to Check It |
| :--- | :--- | :--- |
| `C:\ProgramData\Liongard\ScriptInstall.log` | **Script Logic:** Timestamps and simple messages about what the PowerShell code did. | You see a generalized failure. This log will often point out input errors (Key/Secret). |
| `C:\ProgramData\Liongard\AgentInstall.log` | **MSI Log:** The raw, verbose log created by the Windows Installer. | You see an error related to a system failure (e.g., firewall blocking ports, file lock). |

