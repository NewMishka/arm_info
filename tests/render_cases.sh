#!/usr/bin/env bash
# Shared input cases for the frozen pre-refactor rendering fixture.
render_cases() {
    local COLUMNS
    for COLUMNS in 50 86 95 110 132 180; do
        printf 'WIDTH %s\n' "$COLUMNS"
        print_check_row 'Параметр' '[INFO]' 'Короткое значение'
        print_check_row '' '' ''
        print_check_row 'Certificate with a very long descriptive label' '[WARN]' 'file:///etc/pki/a certificate with spaces.pem; remaining: 125 days'
        print_check_row 'Сетевой ресурс №12 с длинным названием' '[N/A]' 'Не проверен: недостаточно прав; пользователь user@example.test'
        print_check_row $'a\tb\rc\bd' '[OK]' $'first\nsecond\n\nlast\n'
        print_check_row '文字🙂' '[INFO]' '路径/文件/данные'
        print_rec_field 'Что проверить:' 'Проверить DNS, Kerberos и доступность сетевого ресурса в контексте пользователя.'
        print_rec_field '' ''
        print_rec_field 'Длинная метка рекомендации' $'one\ttwo\nthree'
    done
}
