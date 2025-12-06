#!/bin/bash

# Определение цветов и жирного текста для вывода
RED='\033[1;31m'    # Красный жирный
GREEN='\033[1;32m'  # Зеленый жирный
YELLOW='\033[1;33m' # Желтый жирный
BLUE='\033[1;34m'   # Синий жирный
NC='\033[0m'        # Сброс цвета и жирности

# URL файла с подсетями
URL="https://gist.githubusercontent.com/sngvy/07cee7ac810c9d222fbebddff8c1d1b8/raw/974d3d87f190468e134e9b56f1e0a93c7caa0fcd/blacklist.txt"

# Временный файл для хранения подсетей
TEMP_FILE="/tmp/blacklist_subnets.txt"

# Имена наборов ipset
IPSET_V4_NAME="SCANNERS-BLOCK-V4"
IPSET_V6_NAME="SCANNERS-BLOCK-V6"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен от имени root (sudo)${NC}"
    exit 1
fi

# Функция для проверки и установки iptables, ip6tables и ipset
install_iptables_ipset() {
    # iptables
    if ! command -v iptables &>/dev/null; then
        echo -e "${BLUE}Установка iptables...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get update &>/dev/null && apt-get install -y iptables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить iptables${NC}"
                exit 1
            fi
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y iptables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить iptables${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Ошибка: неподдерживаемая система. Установите iptables вручную.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}iptables уже установлен${NC}"
    fi

    # ip6tables
    if ! command -v ip6tables &>/dev/null; then
        echo -e "${BLUE}Установка ip6tables...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get install -y ip6tables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ip6tables${NC}"
                exit 1
            fi
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y ip6tables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ip6tables${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Ошибка: неподдерживаемая система. Установите ip6tables вручную.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}ip6tables уже установлен${NC}"
    fi

    # ipset
    if ! command -v ipset &>/dev/null; then
        echo -e "${BLUE}Установка ipset...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get update &>/dev/null && apt-get install -y ipset &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ipset${NC}"
                exit 1
            fi
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y ipset &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ipset${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Ошибка: неподдерживаемая система. Установите ipset вручную.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}ipset уже установлен${NC}"
    fi
}

# Функция для создания и настройки цепочки SCANNERS-BLOCK для iptables и ip6tables
setup_iptables_chain() {
    # Цепочка для IPv4
    if ! iptables -L SCANNERS-BLOCK -n &>/dev/null; then
        echo -e "${BLUE}Создание цепочки SCANNERS-BLOCK для iptables...${NC}"
        iptables -N SCANNERS-BLOCK
    else
        echo -e "${YELLOW}Очистка существующей цепочки SCANNERS-BLOCK для iptables...${NC}"
        iptables -F SCANNERS-BLOCK
    fi
    # Привязка цепочки к INPUT (IPv4)
    if ! iptables -C INPUT -j SCANNERS-BLOCK &>/dev/null; then
        iptables -A INPUT -j SCANNERS-BLOCK
    fi

    # Цепочка для IPv6
    if ! ip6tables -L SCANNERS-BLOCK -n &>/dev/null; then
        echo -e "${BLUE}Создание цепочки SCANNERS-BLOCK для ip6tables...${NC}"
        ip6tables -N SCANNERS-BLOCK
    else
        echo -e "${YELLOW}Очистка существующей цепочки SCANNERS-BLOCK для ip6tables...${NC}"
        ip6tables -F SCANNERS-BLOCK
    fi
    # Привязка цепочки к INPUT (IPv6)
    if ! ip6tables -C INPUT -j SCANNERS-BLOCK &>/dev/null; then
        ip6tables -A INPUT -j SCANNERS-BLOCK
    fi

    # Правила, использующие ipset
    # IPv4
    if ! iptables -C SCANNERS-BLOCK -m set --match-set "$IPSET_V4_NAME" src -j DROP &>/dev/null; then
        iptables -A SCANNERS-BLOCK -m set --match-set "$IPSET_V4_NAME" src -j DROP
    fi
    # IPv6
    if ! ip6tables -C SCANNERS-BLOCK -m set --match-set "$IPSET_V6_NAME" src -j DROP &>/dev/null; then
        ip6tables -A SCANNERS-BLOCK -m set --match-set "$IPSET_V6_NAME" src -j DROP
    fi
}

# Функция для проверки формата подсети (IPv4 или IPv6)
is_ipv6() {
    local subnet=$1
    if [[ $subnet =~ : ]]; then
        return 0 # IPv6
    else
        return 1 # IPv4
    fi
}

# Функция для создания/очистки ipset наборов
setup_ipset_sets() {
    echo -e "${BLUE}Подготовка ipset наборов...${NC}"

    # IPv4 набор
    if ipset list "$IPSET_V4_NAME" &>/dev/null; then
        echo -e "${YELLOW}Очистка существующего набора ${IPSET_V4_NAME}...${NC}"
        ipset flush "$IPSET_V4_NAME"
    else
        echo -e "${BLUE}Создание набора ${IPSET_V4_NAME} (IPv4)...${NC}"
        ipset create "$IPSET_V4_NAME" hash:net family inet hashsize 1024 maxelem 65536
    fi

    # IPv6 набор
    if ipset list "$IPSET_V6_NAME" &>/dev/null; then
        echo -e "${YELLOW}Очистка существующего набора ${IPSET_V6_NAME}...${NC}"
        ipset flush "$IPSET_V6_NAME"
    else
        echo -e "${BLUE}Создание набора ${IPSET_V6_NAME} (IPv6)...${NC}"
        ipset create "$IPSET_V6_NAME" hash:net family inet6 hashsize 1024 maxelem 65536
    fi
}

# Функция для применения правил ipset (заполнение наборов)
apply_ipset_rules() {
    echo -e "${BLUE}Скачивание списка подсетей...${NC}"
    curl -s "$URL" -o "$TEMP_FILE"
    if [[ ! -s "$TEMP_FILE" ]]; then
        echo -e "${RED}Ошибка: не удалось скачать файл подсетей${NC}"
        exit 1
    fi

    echo -e "${BLUE}Чтение подсетей...${NC}"
    subnets=$(cat "$TEMP_FILE")
    if [[ -z "$subnets" ]]; then
        echo -e "${RED}Ошибка: файл подсетей пуст${NC}"
        exit 1
    fi

    echo -e "${BLUE}Заполнение ipset наборов...${NC}"
    while IFS= read -r subnet; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$subnet" ]] && continue
        [[ "$subnet" =~ ^# ]] && continue

        if is_ipv6 "$subnet"; then
            ipset add "$IPSET_V6_NAME" "$subnet" 2>/dev/null
        else
            ipset add "$IPSET_V4_NAME" "$subnet" 2>/dev/null
        fi
    done <<< "$subnets"
}

# Функция для сохранения правил iptables/ip6tables и ipset
save_iptables_and_ipset() {
    echo -e "${BLUE}Сохранение правил iptables, ip6tables и ipset...${NC}"
    if [[ -f /etc/debian_version ]]; then
        # Проверка и установка netfilter-persistent и iptables-persistent
        if dpkg -l | grep -E '^ii\s+netfilter-persistent\s' >/dev/null || dpkg -l | grep -E '^ii\s+iptables-persistent\s' >/dev/null; then
            echo -e "${GREEN}Пакет netfilter-persistent или iptables-persistent уже установлен${NC}"
        else
            echo -e "${BLUE}Установка netfilter-persistent и iptables-persistent...${NC}"
            apt-get update &>/dev/null
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent &>/dev/null; then
                echo -e "${RED}Ошибка: не удалось установить netfilter-persistent и iptables-persistent${NC}"
                echo -e "${YELLOW}Попробуйте установить вручную: 'apt-get update && apt-get install netfilter-persistent iptables-persistent'${NC}"
            else
                echo -e "${GREEN}Пакеты netfilter-persistent и iptables-persistent успешно установлены${NC}"
            fi
        fi

        # Создание директории /etc/iptables, если она не существует
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила iptables${NC}"
        fi
        ip6tables-save > /etc/iptables/rules.v6
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила ip6tables${NC}"
        fi

        # Сохранение ipset
        ipset save > /etc/iptables/ipset.conf
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить наборы ipset${NC}"
        else
            echo -e "${GREEN}Наборы ipset сохранены в /etc/iptables/ipset.conf${NC}"
            echo -e "${YELLOW}Убедитесь, что ipset восстанавливается при загрузке (через netfilter-persistent или свой юнит/systemd-скрипт).${NC}"
        fi

    elif [[ -f /etc/redhat-release ]]; then
        # Создание директории /etc/sysconfig, если она не существует
        mkdir -p /etc/sysconfig
        iptables-save > /etc/sysconfig/iptables
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила iptables${NC}"
        fi
        ip6tables-save > /etc/sysconfig/ip6tables
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила ip6tables${NC}"
        fi

        # Сохранение ipset
        ipset save > /etc/sysconfig/ipset.conf
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить наборы ipset${NC}"
        else
            echo -e "${GREEN}Наборы ipset сохранены в /etc/sysconfig/ipset.conf${NC}"
            echo -e "${YELLOW}Настройте восстановление ipset при загрузке (через systemd unit с 'ipset restore < /etc/sysconfig/ipset.conf').${NC}"
        fi

        systemctl enable iptables &>/dev/null
        systemctl enable ip6tables &>/dev/null
    else
        echo -e "${YELLOW}Внимание: автоматическое сохранение правил не настроено для этой системы.${NC}"
        echo -e "${YELLOW}Сохраните правила вручную: 'iptables-save > ...', 'ip6tables-save > ...' и 'ipset save > ...' и настройте их восстановление при загрузке.${NC}"
    fi
}

# Основной процесс
echo -e "${BLUE}Запуск скрипта...${NC}"
install_iptables_ipset
setup_ipset_sets
apply_ipset_rules
setup_iptables_chain
save_iptables_and_ipset
rm -f "$TEMP_FILE"
echo -e "${GREEN}Скрипт успешно выполнен!${NC}"
