#!/bin/bash

# Установка зависимостей
echo "Установка необходимых пакетов..."
sudo apt update
sudo apt install -y squid python3 python3-pip

# Установка локалей для поддержки UTF-8
echo "Установка локалей..."
sudo locale-gen ru_RU.UTF-8
sudo update-locale LC_ALL=ru_RU.UTF-8

pip3 install psycopg2-binary requests

# Настройка Squid с защитой от DDoS и черным списком Spamhaus
echo "Настройка Squid с защитой от DDoS и черным списком Spamhaus..."
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak  # Бэкап конфига

# Создание файла для черного списка IP
echo "Загрузка черного списка от Spamhaus..."
sudo mkdir -p /etc/squid/blacklists
wget -q -O - "https://www.spamhaus.org/drop/drop.txt" | grep -v '^;' | awk '{print $1}' | sudo tee /etc/squid/blacklists/spamhaus_drop.txt > /dev/null
wget -q -O - "https://www.spamhaus.org/drop/edrop.txt" | grep -v '^;' | awk '{print $1}' | sudo tee -a /etc/squid/blacklists/spamhaus_drop.txt > /dev/null

# Пример дополнительных IP для черного списка (если Spamhaus недоступен)
cat <<EOL | sudo tee -a /etc/squid/blacklists/spamhaus_drop.txt
1.2.3.4
5.6.7.8
10.0.0.0/24
45.32.0.0/16
185.220.101.0/24
EOL

# Конфигурация Squid
cat <<EOL | sudo tee /etc/squid/squid.conf
http_port 3128
http_access allow all
access_log /var/log/squid/access.log

# Защита от DDoS
maximum_object_size 10 MB          # Ограничение размера объекта
request_body_max_size 15 MB        # Ограничение размера тела запроса
reply_body_max_size 20 MB          # Ограничение размера ответа
cache_mem 256 MB                   # Ограничение памяти кэша
maximum_single_addr 100            # Ограничение запросов с одного IP

# Черный список Spamhaus
acl spamhaus_drop src "/etc/squid/blacklists/spamhaus_drop.txt"
http_access deny spamhaus_drop

# Отключение лишних заголовков для безопасности
forwarded_for off
via off
EOL

# Перезапуск Squid
sudo systemctl restart squid
sudo systemctl enable squid

# Создаем Python-скрипт для управления
cat <<EOL > supplier_manager.py
import os
import time
import psycopg2
import requests
import sys

# Параметры БД
DB_PARAMS = {
    "dbname": "default_db",
    "user": "gen_user",
    "password": "Luq3I)-IGyEEzo",
    "host": "178.253.43.196",
    "port": "5432"
}

# Список стран с эмодзи-флагами перед названием
COUNTRIES = [
    "🇺🇸USA", "🇷🇺Russia", "🇨🇳China", "🇮🇳India", "🇧🇷Brazil",
    "🇩🇪Germany", "🇯🇵Japan", "🇬🇧United Kingdom", "🇫🇷France", "🇮🇹Italy",
    "🇨🇦Canada", "🇰🇷South Korea", "🇦🇺Australia", "🇪🇸Spain", "🇲🇽Mexico",
    "🇮🇩Indonesia", "🇹🇷Turkey", "🇳🇱Netherlands", "🇸🇦Saudi Arabia", "🇨🇭Switzerland",
    "🇩🇰Denmark", "🇳🇴Norway", "🇸🇪Sweden", "🇫🇮Finland", "🇮🇸Iceland",
    "🇭🇰Hong Kong", "🇸🇬Singapore", "🇦🇪United Arab Emirates", "🇿🇦South Africa", "🇹🇭Thailand",
    "🇦🇷Argentina", "🇵🇱Poland", "🇺🇦Ukraine"
]

# Регистрация поставщика
def register_supplier():
    supplier_name = input("Введите ваше наименование как поставщика: ").encode().decode('utf-8', errors='replace')

    print("Выберите способ оплаты:")
    print("1. Криптокошелек")
    print("2. Банковская карта РФ")
    payment_choice = input("Введите номер (1-2): ")

    if payment_choice == "1":
        crypto_wallet = input("Введите адрес криптокошелька: ").encode().decode('utf-8', errors='replace')
        exchange = input("Введите биржу для вывода (например, Binance): ").encode().decode('utf-8', errors='replace')
        payment_method = "crypto"
        card_details = None
    elif payment_choice == "2":
        card_number = input("Введите номер банковской карты (16 цифр): ").encode().decode('utf-8', errors='replace')
        bik = input("Введите БИК банка (9 цифр): ").encode().decode('utf-8', errors='replace')
        cardholder_name = input("Введите имя владельца карты: ").encode().decode('utf-8', errors='replace')
        crypto_wallet = None
        exchange = None
        payment_method = "card"
        card_details = f"{card_number}|{bik}|{cardholder_name}"
    else:
        print("Неверный выбор, используется криптокошелек по умолчанию.")
        crypto_wallet = input("Введите адрес криптокошелька: ").encode().decode('utf-8', errors='replace')
        exchange = input("Введите биржу для вывода (например, Binance): ").encode().decode('utf-8', errors='replace')
        payment_method = "crypto"
        card_details = None

    print("Выберите страну из списка:")
    for i, country in enumerate(COUNTRIES, 1):
        print(f"{i}. {country}")
    country_idx = int(input("Введите номер страны: ")) - 1
    country = COUNTRIES[country_idx].split(" ")[1]  # Убираем эмодзи для записи в БД

    print("Как часто вы хотите получать выплаты?")
    print("1. Раз в две недели")
    print("2. Раз в месяц")
    freq_choice = input("Введите номер (1-2): ")
    payout_frequency = "biweekly" if freq_choice == "1" else "monthly"

    ip = requests.get("https://api.ipify.org").text

    conn = psycopg2.connect(**DB_PARAMS)
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO suppliers (supplier_name, ip_address, country, crypto_wallet, exchange, payout_frequency, payment_method, card_details) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (supplier_name, ip, country, crypto_wallet, exchange, payout_frequency, payment_method, card_details)
    )
    supplier_id = cursor.fetchone()[0]
    conn.commit()
    cursor.close()
    conn.close()
    return supplier_name, ip, supplier_id, payout_frequency, crypto_wallet, exchange, payment_method, card_details

# Подсчет трафика
def get_traffic():
    total_bytes = 0
    log_file = "/var/log/squid/access.log"
    if os.path.exists(log_file):
        with open(log_file, "r") as log:
            for line in log:
                parts = line.split()
                if len(parts) > 4:
                    total_bytes += int(parts[4])
    return total_bytes / (1024 ** 3)  # В гигабайтах

# Обновление трафика и суммы в БД
def update_traffic_in_db(supplier_id, traffic_gb):
    payment = traffic_gb * 1.15  # Сумма в рублях
    conn = psycopg2.connect(**DB_PARAMS)
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE suppliers SET traffic_gb = traffic_gb + %s, amount_due = amount_due + %s WHERE id = %s",
        (traffic_gb, payment, supplier_id)
    )
    conn.commit()
    cursor.close()
    conn.close()

# Удаление поставщика из БД и очистка системы
def remove_supplier(supplier_id):
    conn = psycopg2.connect(**DB_PARAMS)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM suppliers WHERE id = %s", (supplier_id,))
    conn.commit()
    cursor.close()
    conn.close()
    if os.path.exists("supplier_registered"):
        os.remove("supplier_registered")
    print("Ваши данные удалены из системы.")
    print("Для полного удаления софта выполните: sudo apt purge squid && rm -f supplier_manager.py")
    sys.exit(0)

# Вывод инструкции для отправки отчета
def show_report_instructions(supplier_name, supplier_id, ip, crypto_wallet, exchange, payment_method, card_details, traffic_gb):
    payment = traffic_gb * 1.15  # Сумма в рублях
    print("\n=== Инструкция для получения оплаты ===")
    print("Отправьте письмо на supermanformedia@gmail.com со следующими данными:")
    print(f"Имя поставщика: {supplier_name}")
    print(f"IP-адрес сервера: {ip}")
    print(f"Объем трафика: {traffic_gb:.2f} GB")
    print(f"Сумма к оплате: {payment:.2f} ₽")
    if payment_method == "crypto":
        print(f"Криптокошелек: {crypto_wallet}")
        print(f"Биржа: {exchange}")
    else:
        card_number, bik, cardholder_name = card_details.split("|")
        print(f"Номер карты: {card_number}")
        print(f"БИК: {bik}")
        print(f"Имя владельца карты: {cardholder_name}")
    print("После отправки данные будут записаны в нашу базу.")
    update_traffic_in_db(supplier_id, traffic_gb)

# Главное меню
def main_menu(supplier_name, supplier_id, ip, crypto_wallet, exchange, payment_method, card_details):
    while True:
        print("\n=== Меню поставщика услуг ===")
        print("1. Узнать объем трафика")
        print("2. Узнать сумму к оплате")
        print("3. Подготовить отчет для оплаты")
        print("4. Удалить софт и данные")
        print("5. Выход")
        choice = input("Выберите действие (1-5): ")

        traffic_gb = get_traffic()
        if choice == "1":
            print(f"Объем трафика: {traffic_gb:.2f} GB")
        elif choice == "2":
            payment = traffic_gb * 1.15  # Сумма в рублях
            print(f"Сумма к оплате: {payment:.2f} ₽")
        elif choice == "3":
            show_report_instructions(supplier_name, supplier_id, ip, crypto_wallet, exchange, payment_method, card_details, traffic_gb)
            print("Отчет подготовлен, следуйте инструкциям выше!")
        elif choice == "4":
            confirm = input("Вы уверены, что хотите удалить софт и данные? (yes/no): ")
            if confirm.lower() == "yes":
                remove_supplier(supplier_id)
        elif choice == "5":
            sys.exit(0)
        else:
            print("Неверный выбор, попробуйте снова.")

if __name__ == "__main__":
    if not os.path.exists("supplier_registered"):
        supplier_name, ip, supplier_id, payout_frequency, crypto_wallet, exchange, payment_method, card_details = register_supplier()
        with open("supplier_registered", "w") as f:
            f.write(f"{supplier_name}|{supplier_id}|{ip}|{crypto_wallet or ''}|{exchange or ''}|{payment_method}|{card_details or ''}")
        print("Регистрация завершена!")
    else:
        with open("supplier_registered", "r") as f:
            data = f.read().strip().split("|")
            if len(data) != 7:  # Проверка на количество значений
                print("Файл supplier_registered поврежден. Пожалуйста, удалите его и перезапустите регистрацию.")
                sys.exit(1)
            supplier_name, supplier_id, ip, crypto_wallet, exchange, payment_method, card_details = data
            supplier_id = int(supplier_id)
            if payment_method == "crypto" and not crypto_wallet:
                crypto_wallet = None
            if payment_method == "card" and not card_details:
                card_details = None
    main_menu(supplier_name, supplier_id, ip, crypto_wallet, exchange, payment_method, card_details)
EOL

# Регистрация и запуск
echo "Запуск программы..."
python3 supplier_manager.py
