#!/bin/bash




# ./tb_addcustomer.sh admin@example.com password
# 
# chmod +x tb_addcustomer.sh
# ./tb_addcustomer.sh shi***1@gmail.com shi*******

# customers_devices.csv 樣版如下
# CUSTOMER_NAME,CUSTOMER_USER,CUSTOMER_PASS,DEVICE_NAMES
# CustomerA,userA,userApass,"Device1:Tasmota-PZEM:|Device2:Tasmota-PZEM:|Device3:Tasmota-PZEM:"
# CustomerB,userB,userBpass,"Device1:Tasmota-PZEM:客戶B的主電表 {DEVICE}|Device2:Tasmota-PZEM:客戶B的支線電表 {DEVICE}|Device3:Tasmota-PZEM:"
# CustomerC,userC,userCpass,"Device1:Tasmota-PZEM:|Device2:Tasmota-PZEM:|Device3:Tasmota-PZEM:"


# 輸出device_access_tokens.csv 包含
# CUSTOMER,DEVICE,ACCESS_TOKEN,TYPE,DESCRIPTION
# CustomerA,Device1,abcd1234efgh5678,Tasmota-PZEM,客戶 CustomerA 的設備 Device1
# CustomerA,Device2,ijkl9012mnop3456,Tasmota-PZEM,客戶 CustomerA 的設備 Device2
# CustomerA,Device3,qrs6789tuv0123,Tasmota-PZEM,客戶 CustomerA 的設備 Device3
# CustomerB,Device1,wxyz4567abcd8901,Tasmota-PZEM,客戶B的主電表 Device1
# CustomerB,Device2,efgh2345ijkl6789,Tasmota-PZEM,客戶B的支線電表 Device2
# CustomerB,Device3,mnop7890qrst1234,Tasmota-PZEM,客戶 CustomerB 的設備 Device3
# CustomerC,Device1,uvwx5678yzab9012,Tasmota-PZEM,客戶 CustomerC 的設備 Device1
# CustomerC,Device2,cdef3456ghij7890,Tasmota-PZEM,客戶 CustomerC 的設備 Device2
# CustomerC,Device3,klmn0123opqr4567,Tasmota-PZEM,客戶 CustomerC 的設備 Device3


#!/bin/bash
set -e

# =================== 檢查參數 ===================
if [ "$#" -ne 2 ]; then
    echo "使用方式: $0 <TB_ADMIN_USER> <TB_ADMIN_PASS>"
    exit 1
fi

TB_ADMIN_USER="$1"
TB_ADMIN_PASS="$2"
TB_HOST="http://127.0.0.1:8080"
CSV_FILE="customers_devices.csv"
OUTPUT_CSV="device_access_tokens.csv"
EXISTING_CUSTOMER_POLICY="add"  # "add" 或 "skip"
# ==============================================

# 安裝 jq (必要工具)
if ! command -v jq &> /dev/null; then
    echo "安裝 jq..."
    sudo apt install -y jq
fi

# 登入 ThingsBoard
echo "🔑 登入 ThingsBoard 管理員..."
ADMIN_TOKEN=$(curl -s -X POST "$TB_HOST/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$TB_ADMIN_USER\",\"password\":\"$TB_ADMIN_PASS\"}" | jq -r '.token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
    echo "❌ 登入失敗"
    exit 1
fi
echo "✅ 登入成功"

# 初始化輸出 CSV
echo "CUSTOMER,DEVICE,ACCESS_TOKEN,TYPE,DESCRIPTION" > "$OUTPUT_CSV"

# 讀取 CSV
tail -n +2 "$CSV_FILE" | while IFS=',' read -r CUSTOMER_NAME CUSTOMER_USER CUSTOMER_PASS DEVICE_STR; do
    CUSTOMER_NAME=$(echo $CUSTOMER_NAME | xargs)
    CUSTOMER_USER=$(echo $CUSTOMER_USER | xargs)
    CUSTOMER_PASS=$(echo $CUSTOMER_PASS | xargs)
    DEVICE_STR=$(echo $DEVICE_STR | xargs)

    IFS='|' read -ra DEVICES <<< "$DEVICE_STR"

    # 檢查 Customer 是否存在
    EXISTING_CUSTOMER=$(curl -s -X GET "$TB_HOST/api/customers?pageSize=100&page=0" \
        -H "X-Authorization: Bearer $ADMIN_TOKEN" | jq -r --arg NAME "$CUSTOMER_NAME" '.data[] | select(.title==$NAME) | .id.id')

    if [ -n "$EXISTING_CUSTOMER" ]; then
        echo "⚠️ Customer '$CUSTOMER_NAME' 已存在 (ID: $EXISTING_CUSTOMER)"
        if [ "$EXISTING_CUSTOMER_POLICY" = "skip" ]; then
            echo "跳過此 Customer"
            continue
        elif [ "$EXISTING_CUSTOMER_POLICY" = "add" ]; then
            CUSTOMER_ID="$EXISTING_CUSTOMER"
            echo "✅ 將為已存在 Customer 新增設備"
        else
            echo "❌ EXISTING_CUSTOMER_POLICY 設定錯誤"
            exit 1
        fi
    else
        # 建立 Customer
        echo "🏷️ 建立 Customer: $CUSTOMER_NAME..."
        CUSTOMER_ID=$(curl -s -X POST "$TB_HOST/api/customer" \
          -H "Content-Type: application/json" \
          -H "X-Authorization: Bearer $ADMIN_TOKEN" \
          -d "{\"title\":\"$CUSTOMER_NAME\"}" | jq -r '.id.id')
        echo "✅ Customer 建立成功 (ID: $CUSTOMER_ID)"

        # 建立 Customer User
        echo "👤 建立 Customer User: $CUSTOMER_USER..."
        curl -s -X POST "$TB_HOST/api/user" \
          -H "Content-Type: application/json" \
          -H "X-Authorization: Bearer $ADMIN_TOKEN" \
          -d "{
            \"authority\": \"CUSTOMER_USER\",
            \"customerId\": {\"id\":\"$CUSTOMER_ID\"},
            \"email\":\"$CUSTOMER_USER\",
            \"firstName\":\"$CUSTOMER_USER\",
            \"lastName\":\"\",
            \"password\":\"$CUSTOMER_PASS\"
        }" >/dev/null
        echo "✅ Customer User 建立完成"
    fi

    # 建立設備
    for DEV in "${DEVICES[@]}"; do
        IFS=':' read -r DEVICE_NAME DEVICE_TYPE DEVICE_DESC <<< "$DEV"
        DEVICE_NAME=$(echo $DEVICE_NAME | xargs)
        DEVICE_TYPE=$(echo $DEVICE_TYPE | xargs)
        DEVICE_DESC=$(echo $DEVICE_DESC | xargs)

        # 如果 description 空，自動生成
        if [ -z "$DEVICE_DESC" ]; then
            DEVICE_DESC="客戶 $CUSTOMER_NAME 的設備 {DEVICE}"
        fi

        BASE_NAME="$DEVICE_NAME"
        COUNT=1
        while true; do
            EXISTING_DEVICE=$(curl -s -X GET "$TB_HOST/api/customer/$CUSTOMER_ID/devices?pageSize=100&page=0" \
                -H "X-Authorization: Bearer $ADMIN_TOKEN" | jq -r --arg D "$DEVICE_NAME" '.data[] | select(.name==$D) | .id.id')
            if [ -z "$EXISTING_DEVICE" ]; then
                break
            fi
            DEVICE_NAME="${BASE_NAME}_$COUNT"
            COUNT=$((COUNT+1))
        done

        # 替換 description 占位符 {DEVICE}
        DESC_FINAL=${DEVICE_DESC//\{DEVICE\}/$DEVICE_NAME}

        echo "🔧 建立 Device: $DEVICE_NAME..."
        DEVICE_JSON=$(curl -s -X POST "$TB_HOST/api/device" \
          -H "Content-Type: application/json" \
          -H "X-Authorization: Bearer $ADMIN_TOKEN" \
          -d "{
            \"name\": \"$DEVICE_NAME\",
            \"type\": \"$DEVICE_TYPE\",
            \"customerId\": {\"id\":\"$CUSTOMER_ID\"},
            \"additionalInfo\": {\"description\": \"$DESC_FINAL\"}
        }")

        DEVICE_ID=$(echo "$DEVICE_JSON" | jq -r '.id.id')

        # **生成設備 Access Token**
        ACCESS_JSON=$(curl -s -X POST "$TB_HOST/api/device/$DEVICE_ID/credentials" \
          -H "Content-Type: application/json" \
          -H "X-Authorization: Bearer $ADMIN_TOKEN" \
          -d '{"credentialsType":"ACCESS_TOKEN"}')

        ACCESS_TOKEN=$(echo "$ACCESS_JSON" | jq -r '.credentialsId')

        if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
            echo "⚠️ 無法取得 Device $DEVICE_NAME 的 Access Token"
        else
            echo "✅ Device $DEVICE_NAME 建立完成，Access Token: $ACCESS_TOKEN"
        fi

        echo "$CUSTOMER_NAME,$DEVICE_NAME,$ACCESS_TOKEN,$DEVICE_TYPE,$DESC_FINAL" >> "$OUTPUT_CSV"
    done

done

echo "🎉 所有客戶與設備建立完成"
echo "📄 Access Token CSV: $OUTPUT_CSV"
