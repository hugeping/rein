# Схемы подсветки синтаксиса red

Формат схем, которыми редактор red раскрашивает текст. Схема — файл
Lua в `data/lib/red/syntax/<имя>.lua`; имя схемы совпадает с именем
файла, по нему схема включается (окно настроено на схему через
`Syntax <имя>`, пресеты файлов в `data/lib/red/presets.lua` или
`w.kind_conf`, см. примеры ниже).

Движок — `data/lib/red/syntax.lua`; палитра и помощники —
`data/lib/red/scheme.lua` (рядом с `syntax.lua`, а не в `syntax/`,
чтобы их нельзя было загрузить командой `Syntax <имя>`).

## Как движок раскрашивает

Текст буфера — массив символов (`buf.text`, по символу UTF-8 на
элемент). Раскраска хранится в таблице `cols[позиция] = цвет`, которую
движок (`syntax.lua`) заполняет слева направо, по одному символу за
шаг, вызывая `syntax:process(pos, epos)` (позиции растут, переходить
назад нельзя — это учтено механизмами чекпоинтов и инкрементальной
перекраски).

На каждом шаге `process`:

1. назначает текущему символу цвет текущего контекста (`col`);
2. пробует правила текущего контекста — по порядку, первое
   совпадение выигрывает: совпавший текст красится в цвет `scol`
   правила, и это правило становится *текущим контекстом* (старый
   контекст уходит в стек);
3. если ни одно правило не совпало, работает `context`: ключевые
   слова контекста, затем проверка `stop` контекста, иначе символ
   красится цветом контекста и обработка идёт дальше.

Правила проверяются раньше ключевых слов: правило `#` выиграет у
ключевого слова, начинающегося с `#`.

Когда в текущем контексте встречается его `stop`, `stop`-текст
красится в `ecol` (или `col`), контекст снимается со стека, и
обработка возвращается к тому контексту, из которого он был открыт.

Контексты, чей `stop` не задан, не заканчиваются никогда и до конца
текста красятся цветом `col` (их `keywords` продолжают работать) —
задавайте `stop` всем правилам, что открывают контекст на совпадении.
Чтобы закрасить текст разом без контекста, верните его длину функцией
ключевого слова, как `preproc` в c.lua (вся строка `#...`).

## Формат

Файл схемы возвращает таблицу-контекст. Она же — корневой контекст и
список правил:

```lua
local scheme = require "red/scheme"

local col = {
  col = scheme.default,   -- цвет текста контекста
  keywords = {            -- ключевые слова контекста (см. ниже)
    { "and", "end", col = scheme.keyword, word = true },
  },
  {                       -- правило: строковый литерал
    start = '"', stop = '"', col = scheme.string,
    keywords = {          -- экранированная кавычка строку не закрывает
      { '\\"', '\\\\' },
    },
  },
  { -- комментарий до конца строки
    start = '#', stop = '\n', col = scheme.comment,
  },
}

return col
```

### Правило

Поле          | Значение
--------------|---------
`linestart`   | строка или функция; совпадение ищется только в начале строки (перед ним допускаются лишь пробелы и табы, см. `spaces`)
`start`       | строка или функция; совпадение в любом месте контекста
`stop`        | строка или функция — конец контекста (см. ниже)
`spaces`      | Lua-паттерн символов, которые допустимы между началом строки и `linestart` (по умолчанию `"[ \t]"`); чтобы правило срабатывало строго в колонке 0, задайте `spaces = '\n'` — тогда ни один символ, кроме перевода строки, не может стоять перед началом
`scol`        | цвет самого совпавшего начала (`start`/`linestart`); по умолчанию `col`
`col`         | цвет текста внутри контекста
`ecol`        | цвет совпавшего `stop`
`keywords`    | ключевые слова этого контекста (группы, см. ниже)

Один и тот же контекст может быть описан и как `linestart`, и как
`start` — `process` сначала проверяет `linestart`, затем `start`.

Вместо строки допустима функция. Форма:

```lua
{ linestart = function(ctx, txt, i, epos) ... end, ... }
{ start     = function(ctx, txt, i, epos) ... end, ... }
```

- `ctx` — само правило (таблица), `txt` — буфер, `i` — позиция,
  `epos` — конец цветуемого диапазона;
- должна вернуть *длину* совпадения (сколько символов от `i`
  занимает), или `false`/`nil` — нет совпадения;
- только функция `start` может вернуть и второй результат (`aux`):
  он запоминается на стеке вместе с открытым контекстом и достаётся
  функции `stop` этого же контекста — так контекст хранит своё
  состояние (баланс скобок в lua.lua: закрытие обязано иметь столько
  же `=`, сколько открытие).

`stop`:

```lua
stop = '}'                                  -- строка
stop = function(ctx, txt, i, aux) ... end   -- функция
```

Функция `stop` получает (`ctx`, `txt`, `i`, `aux`); вернуть нужно
длину совпадения. Для строкового `stop` движок сам проверяет
совпадение в позиции `i`. Текст `stop` красится в `ecol or col`.

Строковое `start` совпадает только по префиксу. Чтобы проверить
больше — парность, конец слова, что угодно вплоть до `epos` — нужна
функция: ей, в отличие от функции-ключевого-слова, передаётся ещё и
`epos` (как `match` в dir.lua, сканирующий строку).

### keywords

`keywords` контекста — список *групп*; группа — список слов (или
функций) и настроек группы:

```lua
keywords = {
  { "(", ")", "{", "}", col = scheme.operator },
  { "if", "else", "end", col = scheme.keyword, word = true },
  { number, col = scheme.number },      -- функция
  { '\\\\', '\\"' },                    -- без col: цветом контекста
},
```

- слова без `word = true` совпадают как подстроки;
- `word = true` — требуется граница слова с обеих сторон (соседние
  символы не буквы, не цифры и не `_`);
- `word = 'left'` / `'right'` — граница слова только слева / справа;
- `alpha` — свой Lua-паттерн «словесного» символа для проверки
  границ (по умолчанию буквы, цифры и `_`);
- функция-слово получает (`ctx`, `txt`, `pos`) и возвращает длину
  совпадения; она вызывается на *каждой* позиции, поэтому с неё стоит
  начинать с дешёвой проверки первого символа.

Из всех групп контекста побеждает самое длинное совпадение, а при
равной длине — группа, стоящая раньше в списке; найденное слово
красят в `v.col or ctx.col` (поле `ctx.col` — цвет контекста).

### Цвета

Цвет — RGB-таблица `{ r, g, b }`. Схема обычно берёт их из
`scheme.lua`, чтобы темы (`data/lib/red/themes/*.lua`) перекрашивали
подсветку на лету:

- `scheme.default` (`false` — цветом `conf.fg` окна),
- `scheme.keyword`, `scheme.comment`, `scheme.string`,
  `scheme.number`, `scheme.operator`, `scheme.lib`.

Свои цвета можно задавать таблицей напрямую (diff.lua: `{ 0, 190, 0 }`),
но такие цвета темы не перекрашивают.

`col` — цвет «обычного» текста контекста, `scol` — цвет совпавшего
начала правила, `ecol` — цвет совпавшего `stop`. Если `scol`/`ecol`
не заданы, используется `col`.

### Ограничения и тонкости

- Буфер для движка — по одному символу на элемент; слова схемы
  разбираются на символы (`utf.chars`) и сравниваются посимвольно.
- Красится только передний план; фон даёт окно или выделение.
- Все правила хранятся как есть и переиспользуются между окнами:
  не изменяйте таблицы схемы из функций (`tests/syntax_test.lua`
  проверяет это для lua-схемы).
- Совпадение правила красит только *начало* (то, что вернула
  функция или что совпало у строки) и открывает контекст. Если надо
  закрасить длинный кусок разом, не открывая контекст, верните его
  длину функцией ключевого слова — как `preproc` в c.lua, съедающий
  всю строку `#...`.
- Правило может нести и собственные правила: движок перебирает
  массивную часть таблицы текущего контекста, поэтому вложенные
  таблицы-правила внутри правила работают как подправила (но пока
  никто из схем так не делает — вложенность делают `keywords`).
- Движок находит совпадение только *вперёд* от текущей позиции;
  начать раскраску за `epos` нельзя, но совпадение у самой границы
  может захватить и символы за ней (правило красит всю свою длину).

## Общие помощники

Повторяющиеся куски схем живут в `data/lib/red/scheme.lua` — под
`scheme.rule` (цвета палитры занимают имена `scheme.number` и
`scheme.string`, поэтому помощники с такими именами убраны под
`rule`):

- `scheme.rule.bol(txt, i, spaces)` — позиция `i` начинает строку:
  перед ней допустимы только символы паттерна `spaces` (например
  `"[ \t]"` для отступа), без паттерна — ничего;
- `scheme.rule.number` — число в стиле C/Lua (`0x1F`, `1.5e-3`,
  `-7`), не после буквы или цифры; в схеме это ключевое слово:
  `{ scheme.rule.number, col = scheme.number }`;
- `scheme.rule.digits` — просто последовательность цифр (Go, Python);
- `scheme.rule.string(q)` — правило строки в кавычках `q` (`"`, `'`,
  `"""`) с экранированием кавычки и бэкслеша; для бэктика — сырая
  строка без экранирования (Go);
- `scheme.rule.line_comment(mark)` — правило комментария от `mark` до
  конца строки (`//`, `#`, `--`);
- `scheme.rule.block_comment(open, close)` — правило комментария от
  `open` до `close` (`/* */`, `<!-- -->`).

Например, c.lua с ними становится таким:

```lua
local scheme = require "red/scheme"

local col = {
  col = scheme.default,
  keywords = {
    { "if", "else", col = scheme.keyword, word = true },
    { scheme.rule.number, col = scheme.number },
  },
  scheme.rule.block_comment('/*', '*/'),
  scheme.rule.line_comment '//',
  scheme.rule.string '"',
  scheme.rule.string "'",
}

return col
```

## Пример

Схема makefile целиком — `data/lib/red/syntax/makefile.lua`:

```lua
-- Makefile (GNU make and BSD make), on the basis of mc's
-- makefile.syntax: make variables, the directives of the line start,
-- the special targets, the autoconf @..@ substitutions and the
-- recipes (the lines of a real tab).
local scheme = require "red/scheme"

-- $(..) and ${..}, balanced for the same delimiter or to the end of
-- the line; "$$" is the escaped dollar
local function variable(ctx, txt, i)
  if txt[i] ~= '$' then
    return
  end
  if txt[i + 1] == '$' then
    return 2
  end
  local open = txt[i + 1]
  local close = open == '(' and ')' or (open == '{' and '}')
  if not close then
    return
  end
  local depth, j = 1, i + 2
  while txt[j] and txt[j] ~= '\n' do
    if txt[j] == open then
      depth = depth + 1
    elseif txt[j] == close then
      depth = depth - 1
      if depth == 0 then
        return j - i + 1
      end
    end
    j = j + 1
  end
  return j - i
end

-- the autoconf substitutions @foo@
local function autoconf(ctx, txt, i)
  if txt[i] ~= '@' then
    return
  end
  local j = i + 1
  while txt[j] and txt[j] ~= '\n' and txt[j] ~= ' ' and txt[j] ~= '\t' do
    if txt[j] == '@' then
      return j - i + 1
    end
    j = j + 1
  end
end

-- the directives of the line start (column 0): GNU make and BSD make
local direct = {
  define = true, endef = true, include = true, ifdef = true,
  ifndef = true, endif = true, ['if'] = true, ifeq = true,
  ifneq = true, ['else'] = true,
  ['.if'] = true, ['.elif'] = true, ['.else'] = true,
  ['.endif'] = true, ['.for'] = true, ['.endfor'] = true,
  ['.include'] = true, ['.undef'] = true,
}

local function directive(ctx, txt, i)
  if not scheme.rule.bol(txt, i) then
    return
  end
  local n = {}
  local j = i
  while txt[j] and txt[j]:find('[%w_.]') do
    table.insert(n, txt[j])
    j = j + 1
  end
  if #n > 0 and direct[table.concat(n, '')] then
    return #n
  end
end

-- the make variables and continuations live in every context
local refs = {
  { '\\\n', col = scheme.operator },
  { variable, col = scheme.number },
  { autoconf, col = scheme.string },
}

local col = {
  col = scheme.default,
  keywords = {
    { "=", ":", col = scheme.operator },
    { ".PHONY", ".SUFFIXES", ".DEFAULT", ".PRECIOUS",
      ".INTERMEDIATE", ".SECONDARY", ".DELETE_ON_ERROR", ".IGNORE",
      ".LOW_RESOLUTION_TIME", ".SILENT", ".EXPORT_ALL_VARIABLES",
      ".NOTPARALLEL", ".NOEXPORT", col = scheme.lib, word = true },
    { directive, col = scheme.keyword },
    { variable, col = scheme.number },
    { autoconf, col = scheme.string },
    { '\\\n', col = scheme.operator },
  },
  { -- comment: from # to the end of the line
    start = '#',
    stop = '\n',
    col = scheme.comment,
  },
  { -- a recipe: the line starts with a real tab
    linestart = '\t',
    stop = '\n',
    spaces = '\n',
    keywords = refs,
    col = scheme.string,
  },
}

return col
```

## Как подключить

1. Положите файл `data/lib/red/syntax/<имя>.lua`, возвращающий
   таблицу-контекст.
2. Добавьте пресет в `data/lib/red/presets.lua` (или в пользовательский
   `presets.lua` в confdir), например:

```lua
  {"^Makefile", { ts = 8,
    spaces_tab = false,
    trim_spaces = false,
    syntax = "makefile"
    }
  },
```

Схему можно назначить и на лету командой `Syntax <имя>`, и на окно
отдельного вида (`w.kind_conf = { syntax = 'имя' }`, как делают
gemini и irc).

## Тесты

`tests/syntax_test.lua`: `colorize_text(текст, схема)` прогоняет
`process` по всему тексту, затем `s.cols[позиция]` — цвет символа.
Проверки сравнивают цвета с именами `scheme.*`. Добавляйте блок
`it()` на свою схему туда же.
