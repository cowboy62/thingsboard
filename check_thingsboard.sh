#!/bin/bash
# ============================================
#  ThingsBoard 狀態檢查腳本
#  Author: ChatGPT GPT-5
#  適用系統: Ubuntu 20.04+
# ============================================
#sudo chmod +x /usr/local/bin/check_thingsboard.sh
#sudo check_thingsboard.sh



CONF_FILE="/etc/thingsboard/conf/thingsboard.conf"
LOG_FILE="/var/log/thingsboard/thingsboard.log"
SERVICE_NAME="thingsboard"

echo "========== ThingsBoard 狀態檢查 =========="

# Step 1: 檢查服務狀態
echo "[1/6] 檢查 ThingsBoard 服務狀態..."
if systemctl is-active --quiet $SERVICE_NAME; then
  STATUS="🟢 正在執行"
else
  STATUS="🔴 未啟動"
fi
echo "服務狀態: $STATUS"

# Step 2: 顯示服務啟動時間與記憶體使用
echo "[2/6] 系統資源使用..."
systemctl status $SERVICE_NAME --no-pager | grep "Active:" | sed 's/^/   /'
ps -eo pid,comm,%cpu,%mem --sort=-%mem | grep thingsboard | sed 's/^/   /' || echo "   無執行中的進程"

# Step 3: 顯示設定檔資訊
echo "[3/6] 讀取設定檔資訊..."
if [ -f "$CONF_FILE" ]; then
  source <(grep -E "export " "$CONF_FILE" | sed 's/export //')
  echo "資料庫類型:      ${DATABASE_ENTITIES_TYPE:-未設定}"
  echo "資料庫位址:      ${SPRING_DATASOURCE_URL:-未設定}"
  echo "資料庫使用者:    ${SPRING_DATASOURCE_USERNAME:-未設定}"
  echo "資料庫密碼:      ${SPRING_DATASOURCE_PASSWORD:-未設定}"
  echo "HTTP 服務埠:     ${SERVER_HTTP_PORT:-8080}"
  echo "Java 記憶體設定: ${JAVA_OPTS:-未設定}"
else
  echo "⚠️ 找不到設定檔: $CONF_FILE"
fi

# Step 4: 檢查 PostgreSQL 連線狀態
echo "[4/6] 檢查資料庫連線..."
if command -v psql >/dev/null 2>&1; then
  DB_HOST=$(echo "$SPRING_DATASOURCE_URL" | sed -n 's/.*\/\/\(.*\):.*/\1/p')
  DB_NAME=$(echo "$SPRING_DATASOURCE_URL" | sed -n 's/.*\/\(.*\)/\1/p')
  PGPASSWORD=$SPRING_DATASOURCE_PASSWORD psql -h "$DB_HOST" -U "$SPRING_DATASOURCE_USERNAME" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "✅ 資料庫連線正常"
  else
    echo "❌ 無法連線到 PostgreSQL 資料庫"
  fi
else
  echo "⚠️ 系統未安裝 psql，無法測試資料庫連線。"
fi

# Step 5: 檢查開放埠
echo "[5/6] 檢查開放埠..."
for PORT in ${SERVER_HTTP_PORT:-8080} 1883 5683; do
  if ss -ltnup | grep -q ":$PORT"; then
    echo "✅ 埠 $PORT 已開啟"
  else
    echo "❌ 埠 $PORT 未開啟"
  fi
done

# Step 6: 檢查日誌狀態
echo "[6/6] 最近日誌訊息..."
if [ -f "$LOG_FILE" ]; then
  tail -n 5 "$LOG_FILE" | sed 's/^/   /'
else
  echo "⚠️ 找不到日誌檔案: $LOG_FILE"
fi

echo "---------------------------------------------"
echo "預設登入帳號:  tenant@thingsboard.org"
echo "預設登入密碼:  tenant"
echo "訪問網址:      http://$(hostname -I | awk '{print $1}'):${SERVER_HTTP_PORT:-8080}/"
echo "---------------------------------------------"
echo "檢查完成 ✅"
echo "========== ThingsBoard 狀態檢查結束 =========="
