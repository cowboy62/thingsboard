#!/bin/bash
# ============================================
#  ThingsBoard 自動化安裝腳本 (Ubuntu 20.04+)
#  Author: ChatGPT GPT-5
# ============================================
# ✅ 自動偵測 repo 失效時轉用 GitHub .deb 安裝
# ✅ 防止重複初始化、重複建資料庫或使用者
# ✅ 全自動化安裝 (零人工干預)
# ✅ 強化錯誤處理與安全設定
# ✅ 適用 Ubuntu 20.04 / 22.04 / 24.04
#💡 改進說明：

#✅ 自動偵測 repos.thingsboard.io 是否可用，若無法連線 → 自動 fallback 到 GitHub .deb。

#✅ 自動防止重複初始化資料庫 (/usr/share/thingsboard/data/.installed)。

#✅ 支援重複執行，不會破壞已存在的 DB、User。

#✅ 適用於 Ubuntu 20.04、22.04、24.04。

#✅ 全程自動化，無需互動。

#✅ 若出錯會立即停止 (set -e + trap)，確保安全。
### === 可自訂參數區 === ###
TB_VERSION="3.8.1"                   # 最新版本 (可改為 3.6.4 或其他)
TB_DB_NAME="thingsboard"
TB_DB_USER="tb_user"
TB_DB_PASS="tb_pass"
TB_HTTP_PORT="8080"
LOAD_DEMO="false"                     # 是否安裝 demo dashboard (true/false)
### ===================== ###

set -e
trap 'echo "❌ 錯誤發生，腳本中止！"; exit 1' ERR

echo "========== ThingsBoard 自動安裝開始 =========="

# Step 1: 更新系統與安裝依賴
echo "[1/10] 更新系統套件..."
apt update -y && apt upgrade -y
apt install -y wget curl gnupg openjdk-17-jdk postgresql postgresql-contrib ufw

# Step 2: 檢查 Java 版本
JAVA_VER=$(java -version 2>&1 | head -n 1)
echo "[2/10] 已安裝 Java: $JAVA_VER"

# Step 3: 建立或確認 PostgreSQL 資料庫與帳號
echo "[3/10] 檢查 PostgreSQL 資料庫與帳號..."
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TB_DB_NAME'")
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TB_DB_USER'")

if [ "$USER_EXISTS" != "1" ]; then
  echo "🔧 建立使用者 $TB_DB_USER..."
  sudo -u postgres psql -c "CREATE USER $TB_DB_USER WITH PASSWORD '$TB_DB_PASS';"
else
  echo "✅ 使用者 $TB_DB_USER 已存在，略過。"
fi

if [ "$DB_EXISTS" != "1" ]; then
  echo "🔧 建立資料庫 $TB_DB_NAME..."
  sudo -u postgres psql -c "CREATE DATABASE $TB_DB_NAME OWNER $TB_DB_USER;"
else
  echo "✅ 資料庫 $TB_DB_NAME 已存在，略過。"
fi

# Step 4: 嘗試連線官方 repo
echo "[4/10] 嘗試連線 ThingsBoard 官方套件庫..."
if curl -s --head https://repos.thingsboard.io/deb/dists/stable/InRelease | grep "200 OK" >/dev/null; then
  echo "✅ 官方 repo 可用，設定 APT 來源..."
  if [ ! -f /usr/share/keyrings/thingsboard.gpg ]; then
    wget -qO- https://repos.thingsboard.io/repofile.pub.key | gpg --dearmor | sudo tee /usr/share/keyrings/thingsboard.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/thingsboard.gpg] https://repos.thingsboard.io/deb stable main" | sudo tee /etc/apt/sources.list.d/thingsboard.list
  fi
  apt update
  USE_REPO=true
else
  echo "⚠️ 無法連線官方 repo，改用 GitHub 下載安裝包。"
  USE_REPO=false
fi

# Step 5: 安裝 ThingsBoard
echo "[5/10] 安裝 ThingsBoard..."
if dpkg -s thingsboard >/dev/null 2>&1; then
  echo "✅ ThingsBoard 已安裝，略過安裝步驟。"
else
  if [ "$USE_REPO" = true ]; then
    apt install -y thingsboard
  else
    wget -q https://github.com/thingsboard/thingsboard/releases/download/v${TB_VERSION}/thingsboard-${TB_VERSION}.deb -O /tmp/thingsboard.deb
    apt install -y /tmp/thingsboard.deb
  fi
fi

# Step 6: 設定 ThingsBoard 資料庫連線
echo "[6/10] 設定 ThingsBoard 資料庫連線..."
mkdir -p /etc/thingsboard/conf

cat <<EOT > /etc/thingsboard/conf/thingsboard.conf
export DATABASE_ENTITIES_TYPE=sql
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/$TB_DB_NAME
export SPRING_DATASOURCE_USERNAME=$TB_DB_USER
export SPRING_DATASOURCE_PASSWORD=$TB_DB_PASS
export SERVER_HTTP_PORT=$TB_HTTP_PORT
export JAVA_OPTS="-Xms512M -Xmx2048M"
EOT

chown -R thingsboard:thingsboard /etc/thingsboard

# Step 7: 初始化資料庫
echo "[7/10] 初始化資料庫..."
if [ ! -f /usr/share/thingsboard/data/.installed ]; then
  mkdir -p /usr/share/thingsboard/data
  if [ "$LOAD_DEMO" = "true" ]; then
    /usr/share/thingsboard/bin/install/install.sh --loadDemo
  else
    /usr/share/thingsboard/bin/install/install.sh
  fi
  touch /usr/share/thingsboard/data/.installed
  echo "✅ 資料庫初始化完成。"
else
  echo "⚙️ 已初始化過，略過此步驟。"
fi

# Step 8: 啟動 ThingsBoard
echo "[8/10] 啟動 ThingsBoard..."
systemctl daemon-reload
systemctl enable thingsboard
systemctl restart thingsboard

# Step 9: 防火牆設定
echo "[9/10] 設定防火牆規則..."
ufw allow $TB_HTTP_PORT/tcp
ufw allow 1883/tcp
ufw allow 5683/udp
ufw reload || true

# Step 10: 顯示結果
echo "✅ 安裝完成！"
echo "---------------------------------------------"
echo "訪問網址:  http://$(hostname -I | awk '{print $1}'):$TB_HTTP_PORT/"
echo "預設帳號:  tenant@thingsboard.org"
echo "預設密碼:  tenant"
echo "資料庫:    $TB_DB_NAME"
echo "帳號:      $TB_DB_USER"
echo "密碼:      $TB_DB_PASS"
echo "---------------------------------------------"
echo "檢查服務狀態:  sudo systemctl status thingsboard"
echo "查看日誌:      tail -f /var/log/thingsboard/thingsboard.log"
echo "========== ThingsBoard 安裝完成 =========="

