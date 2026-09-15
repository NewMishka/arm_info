from pathlib import Path

p = Path('arm_info.sh')
s = p.read_text(encoding='utf-8')

old = r'''REC_LEVELS=(); REC_TITLES=(); REC_IMPACTS=(); REC_ACTIONS=(); REC_CHECKS=()
add_rec() {
    REC_LEVELS+=("$1"); REC_TITLES+=("$2"); REC_IMPACTS+=("$3");
    REC_ACTIONS+=("$4"); REC_CHECKS+=("${5:-}")
}
'''
new = r'''REC_LEVELS=(); REC_TITLES=(); REC_CAUSES=(); REC_IMPACTS=(); REC_DIAGNOSTICS=(); REC_ACTIONS=(); REC_CHECKS=(); REC_VERIFICATIONS=()
add_rec() {
    local level=$1 title=$2 impact=$3 action=$4 command=${5:-}
    local cause diagnostic verification

    cause="Показатель вышел за нормальное состояние либо его достоверная проверка ограничена. Причину следует подтвердить по фактическому состоянию АРМ и системным журналам."
    diagnostic="Повторно проверить показатель, сопоставить его с журналом текущей загрузки и, если возможно, с исправным АРМ аналогичной конфигурации."
    verification="После устранения первичной причины повторный запуск arm_info должен показать нормализацию показателя и отсутствие новых связанных ошибок."

    case "$title" in
        SMART*)
            cause="SMART недоступен полностью или частично: smartctl может отсутствовать, накопитель/контроллер может не поддерживать прямой SMART-доступ либо требовать иной device type."
            diagnostic="Определить все накопители и способ их подключения, выполнить smartctl --scan-open, затем проверить SMART каждого физического диска и сообщения ядра по storage/I/O."
            verification="SMART должен читаться для всех поддерживаемых фиксированных накопителей; в повторном отчёте полнота диагностики должна увеличиться."
            ;;
        ФС*заполнена*)
            cause="Обычно место занимают пользовательские данные, журналы, кэши, временные файлы, старые пакеты или удалённые, но всё ещё открытые процессами файлы."
            diagnostic="Проверить df, крупнейшие каталоги в пределах этой ФС, размер журналов и наличие удалённых открытых файлов. Перед удалением определить владельца данных и назначение каталога."
            verification="Заполнение должно вернуться ниже предупреждающего порога, запись в ФС должна выполняться без ENOSPC, а рост свободного места — сохраняться после повторной проверки."
            ;;
        Inode*)
            cause="Высокое использование inode обычно связано с очень большим числом мелких файлов: кэшами, spool, временными данными, логами или каталогами приложений."
            diagnostic="Сравнить df -i по точкам монтирования и найти каталоги с аномально большим количеством файлов; не удалять служебные каталоги без понимания назначения."
            verification="Использование inode должно снизиться ниже порога и создание новых файлов должно проходить без ошибки No space left on device."
            ;;
        *read-only*)
            cause="Корневая ФС могла перейти в read-only после ошибок файловой системы, I/O, накопителя, контроллера, кабеля или питания."
            diagnostic="Зафиксировать findmnt и kernel journal, проверить SMART и I/O-ошибки. fsck выполнять только в безопасном режиме на размонтированной файловой системе."
            verification="После устранения причины корневая ФС должна штатно монтироваться RW, а новые filesystem/I/O ошибки не должны появляться в журнале."
            ;;
        *ОЗУ*|*запас ОЗУ*)
            cause="Недостаток доступной памяти может быть вызван реальной рабочей нагрузкой, утечкой памяти, слишком большим числом процессов либо недостаточным объёмом RAM."
            diagnostic="Проверить MemAvailable, swap, крупнейшие процессы по RSS/%MEM и динамику потребления. Одноразовый снимок не считать доказательством утечки."
            verification="При типовой нагрузке должен оставаться стабильный запас MemAvailable, не должно быть новых OOM, а swap не должен постоянно расти из-за дефицита RAM."
            ;;
        *OOM-killer*)
            cause="Ядро исчерпало доступную память/commit и принудительно завершило процесс. Причиной может быть пик нагрузки, утечка, слишком маленький swap либо ограничение cgroup."
            diagnostic="Найти OOM-событие и killed process в kernel journal, проверить состояние памяти до/после инцидента, лимиты cgroup и самые ресурсоёмкие процессы."
            verification="При воспроизведении штатной нагрузки новые OOM-kill события не должны появляться; запас памяти должен оставаться предсказуемым."
            ;;
        *failed-службы*)
            cause="Служба могла завершиться из-за ошибки конфигурации, недоступной зависимости, сети, прав, файла/сертификата или аппаратной проблемы."
            diagnostic="Для каждой failed-unit сначала изучить systemctl status и журнал именно этой unit, начиная с первой ошибки, а не с последствий каскадного сбоя."
            verification="systemctl --failed не должен содержать критичные для АРМ службы; исправленная unit должна быть active либо штатно inactive по своему назначению."
            ;;
        *аппаратные/дисковые ошибки*)
            cause="Kernel hardware/storage errors могут указывать на накопитель, контроллер, кабель, питание, память или драйвер; одна строка журнала не определяет неисправный компонент автоматически."
            diagnostic="Сгруппировать kernel-сообщения по устройству и времени, сопоставить с SMART, I/O counters, EDAC и моментом пользовательского сбоя."
            verification="После исправления аппаратной/связной причины новые I/O/hardware errors не должны появляться, а SMART/EDAC не должны показывать ухудшение."
            ;;
        *journal*)
            cause="Большое число уникальных error-сообщений может быть следствием одной первичной ошибки или нескольких независимых проблем служб/драйверов."
            diagnostic="Отсортировать ошибки по unit/kernel subsystem и времени, определить повторяемость и найти самую раннюю первичную ошибку до каскадных сообщений."
            verification="После исправления первичной причины число новых ошибок за сопоставимый период должно снизиться, а затронутые функции работать стабильно."
            ;;
        *температура CPU*)
            cause="Перегрев возможен из-за пыли, остановки/деградации вентилятора, плохого контакта радиатора, старого термоинтерфейса, высокой температуры среды или длительной нагрузки."
            diagnostic="Сопоставить температуру с текущей нагрузкой, оборотами вентиляторов (если доступны), чистотой системы охлаждения и повторить замер после стабилизации нагрузки."
            verification="При типовой нагрузке температура должна устойчиво оставаться ниже порогов, без thermal throttling и аварийных thermal-сообщений."
            ;;
        *системная нагрузка*)
            cause="Высокий Load Average может означать загрузку CPU или процессы в непрерываемом ожидании I/O; сам Load без контекста не показывает источник."
            diagnostic="Проверить top/ps, процессы в D-state, iostat/vmstat при наличии и нагрузку дисков/сети; сравнить с нормальной рабочей нагрузкой."
            verification="После устранения источника Load1 должен соответствовать числу потоков CPU и штатному профилю нагрузки, а задержки пользователя исчезнуть."
            ;;
        Эксплуатационный*)
            cause="Возраст является только эксплуатационным ориентиром, а не доказательством износа конкретного узла. Риск оценивается вместе со SMART, охлаждением, БП и историей сбоев."
            diagnostic="Проверить резервное копирование, SMART/наработку накопителей, охлаждение, состояние вентиляторов и историю аппаратных ошибок."
            verification="План профилактики/замены должен учитывать фактические показатели и критичность АРМ; сама возрастная рекомендация после обслуживания может оставаться."
            ;;
        *активный IPv4-интерфейс*)
            cause="Нет рабочего IPv4 из-за link down, кабеля/порта, драйвера, NetworkManager-профиля, DHCP/статической настройки или сетевой аутентификации."
            diagnostic="Проверить link/state, адреса, активный профиль, журнал NetworkManager и при наличии 802.1X — состояние EAP/сертификатов."
            verification="Интерфейс должен быть UP с корректным IPv4, маршрутом и DNS; необходимые инфраструктурные узлы должны быть доступны."
            ;;
        *маршрут по умолчанию*)
            cause="Default route отсутствует из-за неполной IP-конфигурации, сетевого профиля или ошибки DHCP/статического шлюза."
            diagnostic="Сопоставить ip route с параметрами активного NetworkManager-профиля и проверить достижимость предполагаемого шлюза."
            verification="Должен появиться корректный default route через ожидаемый интерфейс; маршрутизация до нужных сетей должна проходить без обходных ручных правил."
            ;;
        *DNS-серверы не определены*)
            cause="DNS не получен/не задан в активном профиле либо generated resolv.conf/stub не содержит рабочего upstream."
            diagnostic="Проверить resolv.conf, resolvectl (если используется), NetworkManager IP4.DNS/IP4.DOMAIN и разрешение FQDN/доменных SRV."
            verification="Должны определяться рабочие DNS upstream и стабильно разрешаться FQDN, включая необходимые доменные SRV-записи."
            ;;
        *сетевых ошибок/дропов*)
            cause="Рост RX/TX errors/dropped возможен из-за физического линка, порта коммутатора, перегрузки, драйвера, очередей NIC или несогласованных параметров."
            diagnostic="Снять ip -s link несколько раз с интервалом, определить конкретный интерфейс и скорость роста счётчиков; проверить ethtool/драйвер и порт сети при наличии доступа."
            verification="Счётчики ошибок/дропов не должны заметно расти при нормальной нагрузке; ppm должен вернуться ниже порогов arm_info."
            ;;
        *время не синхронизировано*)
            cause="NTP/chrony источник недоступен, служба времени остановлена, неверно настроена либо системное время слишком сильно отклонено."
            diagnostic="Проверить timedatectl, chronyc tracking/sources, журнал службы времени и сетевую доступность разрешённых NTP-источников."
            verification="Система должна показывать синхронизацию, а offset/stratum — стабильные значения; Kerberos не должен выдавать ошибки, связанные со временем."
            ;;
        *аварийного завершения*)
            cause="Предыдущая загрузка могла завершиться из-за отключения питания, зависания, kernel panic/watchdog, аппаратного сбоя или принудительной перезагрузки."
            diagnostic="Изучить конец журнала предыдущей загрузки, last -x, kernel warning/error и сопоставить время с внешними событиями/обращением пользователя."
            verification="Последующие выключения/перезагрузки должны быть штатными; признаки panic/watchdog/I/O/power ошибок не должны повторяться."
            ;;
        *RAID*DEGRADED*)
            cause="Software RAID потерял резервирование: один или несколько членов массива отсутствуют/failed/removed либо идёт незавершённое восстановление."
            diagnostic="Проверить /proc/mdstat и mdadm --detail всех md-устройств, затем SMART каждого физического члена."
            verification="Массив должен вернуться в clean/active с ожидаемым числом членов; resync/recovery должен завершиться без новых disk errors."
            ;;
        ECC:*)
            cause="EDAC зафиксировал исправленные или неисправимые ошибки памяти. Причиной может быть DIMM, слот, контроллер памяти, питание или редкий transient event."
            diagnostic="Зафиксировать CE/UE по контроллерам/каналам, проверить рост счётчиков, журнал EDAC/MCE и провести аппаратный memory test в окно обслуживания."
            verification="UE не должны повторяться; CE не должны расти систематически. После замены/перестановки модуля счётчики и аппаратные тесты должны быть стабильны."
            ;;
        *батареи*)
            cause="Расчётная full capacity заметно ниже design capacity; это типичный признак естественного износа аккумулятора."
            diagnostic="Сопоставить energy-full/design, cycle count (если доступен), реальную автономность и наличие внезапных падений заряда."
            verification="После замены/обслуживания health и фактическая автономность должны соответствовать требованиям; при сохранении батареи контролировать дальнейшую деградацию."
            ;;
        SSSD*)
            cause="SSSD установлен, но не активен/нештатен; возможны ошибки конфигурации, DNS, времени, Kerberos, доступа к DC или локальной БД SSSD."
            diagnostic="Проверить status, config-check/domain-list и journalctl -u sssd; отдельно убедиться в корректности DNS и времени до очистки кэшей или повторного join."
            verification="SSSD должен быть active, домен доступен, разрешение пользователей/групп и штатная доменная аутентификация должны проходить без новых ошибок."
            ;;
        CUPS*)
            cause="CUPS не активен при настроенных очередях из-за ошибки службы, backend, конфигурации, фильтра, аутентификации или устройства."
            diagnostic="Проверить cups.service, scheduler, lpstat -p/-v, незавершённые jobs и журнал CUPS до попытки возобновления/очистки очереди."
            verification="CUPS должен быть active, scheduler отвечать, нужные очереди не быть paused, а тестовое задание завершаться штатно."
            ;;
    esac

    REC_LEVELS+=("$level"); REC_TITLES+=("$title"); REC_CAUSES+=("$cause"); REC_IMPACTS+=("$impact")
    REC_DIAGNOSTICS+=("$diagnostic"); REC_ACTIONS+=("$action"); REC_CHECKS+=("$command"); REC_VERIFICATIONS+=("$verification")
}
'''
if old not in s:
    raise SystemExit('recommendation array/add_rec block not found')
s = s.replace(old, new, 1)

old_text = r'''   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"; print_wrapped "Действие:" "${REC_ACTIONS[$i]}"; [ -n "${REC_CHECKS[$i]}" ]&&print_wrapped "Команда:" "${REC_CHECKS[$i]}"
'''
new_text = r'''   print_wrapped "Причины:" "${REC_CAUSES[$i]}"
   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"
   print_wrapped "Проверить:" "${REC_DIAGNOSTICS[$i]}"
   print_wrapped "Действие:" "${REC_ACTIONS[$i]}"
   [ -n "${REC_CHECKS[$i]}" ]&&print_wrapped "Команда:" "${REC_CHECKS[$i]}"
   print_wrapped "Контроль:" "${REC_VERIFICATIONS[$i]}"
'''
if old_text not in s:
    raise SystemExit('text recommendation rendering not found')
s = s.replace(old_text, new_text, 1)

old_json = r'''        printf '\n    {"level":"%s","title":"%s","impact":"%s","action":"%s","command":"%s"}' \
            "$(json_escape "${REC_LEVELS[$i]}")" "$(json_escape "${REC_TITLES[$i]}")" "$(json_escape "${REC_IMPACTS[$i]}")" \
            "$(json_escape "${REC_ACTIONS[$i]}")" "$(json_escape "${REC_CHECKS[$i]}")"
'''
new_json = r'''        printf '\n    {"level":"%s","title":"%s","possible_causes":"%s","impact":"%s","checks":"%s","action":"%s","command":"%s","verification":"%s"}' \
            "$(json_escape "${REC_LEVELS[$i]}")" "$(json_escape "${REC_TITLES[$i]}")" "$(json_escape "${REC_CAUSES[$i]}")" \
            "$(json_escape "${REC_IMPACTS[$i]}")" "$(json_escape "${REC_DIAGNOSTICS[$i]}")" "$(json_escape "${REC_ACTIONS[$i]}")" \
            "$(json_escape "${REC_CHECKS[$i]}")" "$(json_escape "${REC_VERIFICATIONS[$i]}")"
'''
if old_json not in s:
    raise SystemExit('json recommendation rendering not found')
s = s.replace(old_json, new_json, 1)

p.write_text(s, encoding='utf-8')

# Static regression guard for the richer base recommendation format.
tp = Path('tests/test_cli.sh')
t = tp.read_text(encoding='utf-8')
extra = r'''
grep -q 'print_wrapped "Причины:"' "$SCRIPT" || die "base recommendation causes"
grep -q 'print_wrapped "Проверить:"' "$SCRIPT" || die "base recommendation checks"
grep -q 'print_wrapped "Контроль:"' "$SCRIPT" || die "base recommendation verification"
grep -q '"possible_causes"' "$SCRIPT" || die "base recommendation JSON causes"
grep -q '"verification"' "$SCRIPT" || die "base recommendation JSON verification"
'''
anchor = 'bash "$SCRIPT" --help | grep -q -- \'--privacy\' || die "--help"\n'
if 'base recommendation causes' not in t:
    if anchor not in t:
        raise SystemExit('test_cli anchor not found')
    t = t.replace(anchor, anchor + extra, 1)
tp.write_text(t, encoding='utf-8')
