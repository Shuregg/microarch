# Cache Refill Controller

Проект содержит параметризуемый read-only cache controller на SystemVerilog с refill из внешней памяти, отдельной state-SRAM для `valid`/LRU-состояния и тестбенчем для базовой проверки refill, hit/miss и вытеснения.

> Важно: текущая версия `cache_ctrl` реализована как blocking FSM-контроллер. Имена состояний близки к планировавшимся стадиям, но независимых pipeline-регистров `valid/ready` между стадиями пока нет.

## Структура проекта

- `rtl/cache_ctrl.sv` - основная RTL-логика контроллера кэша.
- `rtl/cache_top.sv` - top-level wrapper, который инстанцирует контроллер, cache-SRAM и state-SRAM.
- `rtl/cache_sram_model.sv` - синхронная однопортовая SRAM-модель с latency 1 такт.
- `rtl/cache_param_pkg.sv` - параметры конфигураций кэша.
- `dv/cache_if.sv` - testbench interface.
- `dv/tb_cache.sv` - self-checking testbench.
- `run/Makefile` - запуск Xcelium/xrun-симуляции.

## Поддерживаемые конфигурации

Конфигурация выбирается define-ом `CACHE_TYPE` в `run/Makefile`:

- `DIRECT_MAPPED_CACHE`: `SETS=8`, `WAYS=1`.
- `FOUR_WAY_SET_ASSOCIATIVE_CACHE`: `SETS=2`, `WAYS=4`.
- `FULLY_ASSOCIATIVE_CACHE`: `SETS=1`, `WAYS=8`.

Общие параметры:

- `DATA_WIDTH=32`.
- `ADDR_WIDTH=30`.
- `SET_WIDTH = (SETS != 1) ? $clog2(SETS) : 1`.
- `TAG_WIDTH = (SETS != 1) ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH`.

Адрес декодируется как `{tag, set}` для `SETS != 1`. Для fully-associative режима весь адрес считается tag-ом, а set принудительно равен нулю.

## RTL-имплементация

### Памяти

В `cache_top` используются две независимые однопортовые SRAM-модели:

1. `u_cache_sram`
   - хранит tag и data всех way-ев одного set-а;
   - ширина строки:

```systemverilog
CACHE_CELL_WIDTH = WAYS * (TAG_WIDTH + DATA_WIDTH)
```

2. `u_state_sram`
   - хранит служебное состояние всех way-ев одного set-а;
   - на каждый way приходится:

```systemverilog
typedef struct packed {
    logic                         valid;
    logic [LRU_CNT_WIDTH - 1 : 0] lru_age;
} state_way_t;
```

   - ширина строки:

```systemverilog
STATE_WAY_WIDTH  = 1 + LRU_CNT_WIDTH
STATE_CELL_WIDTH = WAYS * STATE_WAY_WIDTH
```

Например, для `FOUR_WAY_SET_ASSOCIATIVE_CACHE`:

- `SETS=2`;
- `WAYS=4`;
- `LRU_CNT_WIDTH=2`;
- `STATE_WAY_WIDTH=3`;
- `STATE_CELL_WIDTH=12`.

Логически одна строка state-SRAM выглядит так:

```text
state_sram[set] = {
  way3: {valid, lru_age[1:0]},
  way2: {valid, lru_age[1:0]},
  way1: {valid, lru_age[1:0]},
  way0: {valid, lru_age[1:0]}
}
```

### Интерфейсы

Входной запрос принимается при:

```systemverilog
s_valid_i && s_ready_o
```

Выходной ответ валиден при:

```systemverilog
m_valid_o
```

`data_o` и `hit_o` удерживаются до приема ответа через `m_ready_i`. Для совместимости `hit_valid_o` сделан алиасом `m_valid_o`.

Для внешней памяти используется простой pulse-протокол:

- при miss `ext_mem_req_o` поднимается на один такт;
- `ext_mem_addr_o` содержит miss-адрес и удерживается до `ext_mem_ack_i`;
- `ext_mem_data_i` сэмплируется в такт `ext_mem_ack_i`;
- одновременно поддерживается только один outstanding miss.

### FSM контроллера

Текущее поведение описано состояниями:

- `ST_INIT` - после reset последовательно записывает нули во все строки state-SRAM. Пока инициализация не закончена, `s_ready_o=0`.
- `ST_READY` - контроллер готов принять новый read-запрос. При `s_valid_i` запускается чтение cache-SRAM и state-SRAM.
- `ST_CHECK_TAG` - проверяются `valid` и tag по всем way-ям выбранного set-а.
- `ST_MEM_WAIT` - при miss ожидается `ext_mem_ack_i`, затем выполняется refill cache-SRAM и обновление state-SRAM.
- `ST_OUTPUT` - результат удерживается на выходе до `m_ready_i`.

Из-за однопортовых SRAM и blocking FSM контроллер обрабатывает один запрос за раз. Новые запросы не принимаются во время проверки, обновления LRU, ожидания памяти, refill и backpressure на выходе.

### Hit path

На hit:

- выбирается way, у которого `valid=1` и tag совпал;
- `data_o` получает data из cache-SRAM;
- `hit_o=1`;
- state-SRAM обновляется по LRU-правилам;
- результат выдается через `m_valid_o`.

### Miss/refill path

На miss:

- выбирается victim way;
- выдается one-cycle pulse `ext_mem_req_o`;
- контроллер ждет `ext_mem_ack_i`;
- полученное `ext_mem_data_i` записывается в cache-SRAM вместе с новым tag;
- выбранный way становится valid и получает `lru_age=0`;
- результат выдается с `hit_o=0`, но `data_o` валиден.

## LRU-алгоритм

В state-SRAM не хранится номер LRU way-а. Вместо этого для каждого way хранится возраст `lru_age`.

Принятая интерпретация:

- `lru_age=0` - MRU, most recently used;
- максимальный `lru_age` - LRU, least recently used.

Victim выбирается так:

1. Если есть invalid way, выбирается младший invalid way.
2. Если все way-и valid, выбирается way с максимальным `lru_age`.
3. При равенстве возрастов приоритет остается у младшего индекса way.

На hit:

- hit-way получает `lru_age=0`;
- валидные way-и, которые были моложе hit-way, стареют на 1;
- остальные way-и не меняются.

На refill:

- victim-way получает `valid=1` и `lru_age=0`;
- остальные valid way-и стареют на 1;
- invalid way-и остаются invalid с `lru_age=0`.

## Тестбенч

`dv/tb_cache.sv` является self-checking testbench-ем. Он не использует `$readmemh` и не пишет напрямую во внутренние массивы DUT. Вместо этого используется модель внешней памяти.

### Модель внешней памяти

`ext_mem_model_proc`:

- ловит pulse `ext_mem_req`;
- запоминает `ext_mem_addr`;
- ждет `ext_mem_delay` тактов;
- возвращает `ext_mem_data`;
- поднимает `ext_mem_ack` на один такт.

Данные внешней памяти детерминированно вычисляются из адреса:

```systemverilog
ext_mem_data_for_addr(addr) = addr ^ 32'hcace_0001
```

### Общие TB helpers

- `apply_reset()` - сбрасывает DUT и ждет завершения init-прохода state-SRAM по `s_ready`.
- `send_read_request(addr)` - отправляет read-запрос по `s_valid/s_ready`.
- `wait_for_response()` - ждет `m_valid`, считывает `hit` и `data`, проверяет выравнивание `hit_valid` с `m_valid`.
- `check_read(addr, exp_hit)` - выполняет read и проверяет hit/miss, data и количество `ext_mem_req` pulse-ов.

### Тестовые сценарии

1. `check_first_miss_then_hit`
   - после reset первый доступ к адресу должен дать miss;
   - данные приходят из внешней памяти;
   - повторный доступ к тому же адресу должен дать hit без нового `ext_mem_req`.

2. `check_delayed_miss_stall`
   - увеличивает задержку внешней памяти;
   - проверяет, что во время outstanding miss `s_ready_o=0`;
   - проверяет, что на miss выдается ровно один `ext_mem_req` pulse.

3. `check_invalid_first_replacement`
   - последовательно заполняет set разными tag-ами;
   - пока есть invalid way-и, новые строки должны занимать их без вытеснения уже заполненных way-ев;
   - ранее заполненные строки перечитываются как hit.

4. `check_lru_replacement`
   - заполняет все way-и одного set-а;
   - делает один из tag-ов MRU повторным обращением;
   - вставляет новый tag;
   - проверяет, что вытеснен ожидаемый LRU way.

5. `check_output_backpressure`
   - создает cached hit;
   - опускает `m_ready_i`;
   - проверяет, что `m_valid_o`, `hit_o` и `data_o` удерживаются стабильными;
   - проверяет, что новые запросы не принимаются, пока ответ backpressured.

Дополнительно `ext_mem_req_monitor` считает количество `ext_mem_req` и проверяет, что request pulse не длится больше одного такта.

## Assertions

В `cache_ctrl` присутствуют проверки:

- корректность параметра `SETS`;
- корректность параметра `WAYS`;
- согласованность ширин tag/set;
- не более одного hit-way одновременно;
- отсутствие X на принятом адресе;
- `ext_mem_req_o` является one-cycle pulse.

## Запуск симуляции

Из директории `run`:

```sh
make sim
```

Выбор конфигурации:

```sh
make sim CACHE_TYPE=DIRECT_MAPPED_CACHE
make sim CACHE_TYPE=FOUR_WAY_SET_ASSOCIATIVE_CACHE
make sim CACHE_TYPE=FULLY_ASSOCIATIVE_CACHE
```

Просмотр waveform:

```sh
make view
```

Очистка результатов:

```sh
make clean
```

## Текущие ограничения

- Контроллер read-only: операций записи со стороны slave-интерфейса нет.
- Cache line равна одному слову `DATA_WIDTH`.
- Одновременно поддерживается только один outstanding miss.
- Текущая RTL-реализация blocking FSM, а не полноценный pipeline с независимыми stage-registers.
- SRAM-модель однопортовая, поэтому чтение и запись одной SRAM в один такт не поддерживаются.
