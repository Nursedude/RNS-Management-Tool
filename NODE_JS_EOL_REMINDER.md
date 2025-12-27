# ⚠️ IMPORTANT: Node.js 18 End of Life Reminder

## Critical Timeline Alert

### Node.js 18 LTS Reaches End of Life (EOL)
**📅 Date: April 30, 2025**
**⏱️ Time Remaining: ~4 months from now (as of Dec 27, 2024)**

---

## What This Means

### Before This Fix (Old Script Behavior)
The original `reticulum_updater.sh` installed Node.js via:
```bash
sudo apt install nodejs npm
```

This would install:
- **Node.js 18.19.1** (from Ubuntu/Debian repositories)
- **npm 9.2.0** (severely outdated)

### Why This Was a Problem

1. **Node.js 18 EOL Timeline:**
   - **Now → April 2025:** Still receives security updates
   - **After April 30, 2025:** NO MORE SECURITY UPDATES
   - **Impact:** Known vulnerabilities will remain unpatched

2. **MeshChat Dependency Requirements:**
   - Modern npm packages are dropping support for Node.js 18
   - Many dependencies now require Node.js 20+ or 22+
   - Build failures expected within 3-6 months even before EOL
   - npm 9 is incompatible with many current packages

3. **npm Version Issues:**
   - npm 9.2.0 is 2+ major versions behind (current: 11.7.0)
   - Missing critical security fixes
   - Missing features that modern packages rely on
   - Known bugs that cause build failures

---

## ✅ What Has Been Fixed (Current Script)

The updated script now:

1. **Installs Modern Node.js** via NodeSource repository:
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs
   ```
   - Installs **Node.js 22.x LTS** (supported until April 2027)
   - Includes **npm 10.x+** (modern, secure version)

2. **Checks Node.js Version** before MeshChat operations:
   - Verifies Node.js ≥ 18
   - Prompts to upgrade if too old
   - Prevents build failures

3. **Updates npm Automatically** if older than version 10

4. **Runs Security Audits** after package installation:
   - `npm audit` to detect vulnerabilities
   - `npm audit fix` to auto-fix moderate issues
   - Logs results for review

---

## Node.js Release Schedule Reference

| Version | Release Date | Active LTS Start | Maintenance Start | End of Life |
|---------|--------------|------------------|-------------------|-------------|
| Node 18 | 2022-04-19   | 2022-10-25      | 2023-10-18        | **2025-04-30** ⚠️ |
| Node 20 | 2023-04-18   | 2023-10-24      | 2024-10-22        | 2026-04-30 |
| Node 22 | 2024-04-24   | 2024-10-29      | 2025-10-21        | **2027-04-30** ✅ |

**Current Fix:** Uses Node.js 22 LTS → Safe until 2027

---

## What Would Have Happened Without This Fix

### Timeline of Consequences:

#### **Immediate (Dec 2024 - Jan 2025)**
- ✅ Script works
- ⚠️ Installing deprecated software
- ⚠️ npm warnings about old version

#### **Short Term (Feb - April 2025)**
- 🟡 Increasing npm package incompatibilities
- 🟡 MeshChat build warnings
- 🟡 Some dependencies fail to install
- 🟡 Security vulnerability warnings

#### **April 30, 2025 - Node.js 18 EOL**
- 🔴 No more security patches
- 🔴 Growing list of unpatched vulnerabilities
- 🔴 npm packages start dropping Node 18 support

#### **Post-EOL (May - Dec 2025)**
- 🔴 MeshChat builds fail completely
- 🔴 Cannot install new packages
- 🔴 Security vulnerabilities accumulate
- 🔴 Users forced to manually fix installations
- 🔴 Repository appears unmaintained

---

## MeshChat Dependency Requirements

### Current MeshChat Requirements
Based on the reticulum-meshchat repository:

```json
{
  "engines": {
    "node": ">=18.0.0",
    "npm": ">=9.0.0"
  }
}
```

### Future Expected Requirements (2025-2026)
Many MeshChat dependencies will likely require:
- **Node.js 20+** (as 18 goes EOL)
- **npm 10+** (current standard)

### Common Dependencies Affected:
- **Electron** - Requires modern Node.js for latest versions
- **Vue/React** - Modern build tools need Node 18+ minimum
- **Webpack/Vite** - Build tools requiring latest Node.js features
- **npm packages** - Many dropping support for EOL Node versions

---

## Testing Recommendations

### After Running Updated Script, Verify:

1. **Node.js Version:**
   ```bash
   node --version
   # Should show: v22.x.x or higher
   ```

2. **npm Version:**
   ```bash
   npm --version
   # Should show: 10.x.x or higher
   ```

3. **MeshChat Installation:**
   ```bash
   cd ~/reticulum-meshchat
   npm install  # Should complete without errors
   npm audit    # Should show minimal/no critical issues
   npm run build  # Should build successfully
   ```

4. **Security Audit:**
   ```bash
   cd ~/reticulum-meshchat
   npm audit --audit-level=moderate
   # Review and address any findings
   ```

---

## Future-Proofing Recommendations

### Every 6 Months:
- [ ] Check Node.js release schedule: https://nodejs.org/en/about/previous-releases
- [ ] Verify current LTS version
- [ ] Update NodeSource setup script if needed
- [ ] Test MeshChat build

### Every Year:
- [ ] Review MeshChat dependencies
- [ ] Update to latest Node.js LTS if available
- [ ] Run comprehensive security audit
- [ ] Test all Reticulum ecosystem components

### Monitor These Resources:
- 🔗 Node.js Release Schedule: https://github.com/nodejs/release#release-schedule
- 🔗 NodeSource Distributions: https://github.com/nodesource/distributions
- 🔗 MeshChat Repository: https://github.com/liamcottle/reticulum-meshchat
- 🔗 npm Security Advisories: https://www.npmjs.com/advisories

---

## Emergency Rollback (If New Script Causes Issues)

If the updated script causes problems:

1. **Use Backup Script:**
   ```bash
   git checkout HEAD~1 reticulum_updater.sh
   ```

2. **Manual Node.js Installation (Alternative Methods):**
   ```bash
   # Option 1: nvm (Node Version Manager)
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
   source ~/.bashrc
   nvm install --lts
   nvm use --lts

   # Option 2: Direct from NodeSource (used in script)
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
   sudo apt install -y nodejs

   # Option 3: Snap (alternative package manager)
   sudo snap install node --classic --channel=22
   ```

3. **Report Issue:**
   - Open issue at: https://github.com/Nursedude/RNS-updater/issues
   - Include error logs from `~/reticulum_update_*.log`
   - Include Node.js and npm versions

---

## Summary Checklist

✅ **What Was Fixed:**
- [x] Replaced deprecated `apt install nodejs npm` with NodeSource
- [x] Added Node.js version checking before MeshChat operations
- [x] Added automatic npm updates if version < 10
- [x] Added npm security audits after package installation
- [x] Added fallback to system packages if NodeSource fails
- [x] Updated both `install_meshchat()` and `update_meshchat()` functions

✅ **Why It Matters:**
- [x] Prevents installing end-of-life software
- [x] Ensures MeshChat builds succeed
- [x] Improves security posture
- [x] Future-proofs the script through 2027

✅ **What To Remember:**
- [x] Node.js 18 EOL: **April 30, 2025** (~4 months away)
- [x] Current fix uses Node.js 22 LTS (safe until 2027)
- [x] Modern MeshChat builds require Node 18+ minimum
- [x] npm 10+ is required for modern package ecosystem

---

**🎯 Bottom Line:**
The script is now future-proof and will install modern, supported software that will work reliably through 2027 instead of installing software that becomes unsupported in 4 months.

---

**📅 Set Your Calendar Reminders:**
- **March 2025:** Review Node.js 22 status, plan for Node 24 migration if needed
- **October 2025:** Check if Node.js 24 LTS is available
- **March 2027:** Start planning Node.js 22 EOL transition

---

*Last Updated: 2025-12-27*
*Next Review Recommended: March 2025*
