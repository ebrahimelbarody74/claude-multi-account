# claude-multi-account

<div dir="rtl">

شغّل أكثر من حساب **Claude Code** جنبًا إلى جنب وبدّل بينها فورًا — بدون دورة
`logout` / `login` في كل مرة، وبدون فقدان الجلسات.

> English README: [README.md](README.md)

</div>

```console
$ claude-account list
ACCOUNT            EMAIL                              PLAN       STATUS
default            me@personal.com                    max        logged in *
work               me@company.com                     max        logged in
client             hello@client.io                    pro        logged in

$ claude-account work            # جلسة Claude Code بهوية me@company.com
$ claude-account client -p "review this PR"
$ claude-account default         # حساب Claude Code الأصلي كما هو
```

<div dir="rtl">

كل حساب يحتفظ بتسجيل دخوله وإعداداته وخوادم MCP ومشاريعه وسجلّه **بشكل مستقل**.
تسجيل الدخول في حساب لا يُخرجك أبدًا من حساب آخر.

---

## المحتويات

- [لماذا](#لماذا)
- [التثبيت](#التثبيت)
- [الأوامر](#الأوامر)
- [أمثلة](#أمثلة)
- [كيف يعمل](#كيف-يعمل)
- [الأمان](#الأمان)
- [حل المشكلات](#حل-المشكلات)
- [إزالة التثبيت](#إزالة-التثبيت)
- [الرخصة](#الرخصة)

---

## لماذا

يخزّن Claude Code هوية واحدة مسجَّلة الدخول في المرة الواحدة. فإذا كان لديك حساب
عمل وحساب شخصي، فالتبديل بينهما يعني تسجيل خروج ثم تسجيل دخول — وفقدان الحالة
المحلية لتلك الجلسة في الاتجاهين.

تمنح هذه الأداة كل حساب **`CLAUDE_CONFIG_DIR`** خاصًا به. فيصبح التبديل كلمة
واحدة في سطر الأوامر، وتبقى كل الحسابات مسجَّلة الدخول في الوقت نفسه.

**الأداة لا تُعدّل `HOME` إطلاقًا.** بعض الحيل لتعدّد الحسابات تُعيد توجيه `HOME`
إلى مجلد منزل وهمي؛ وهذا على macOS يُعطّل الوصول إلى Keychain ويُنتج أخطاء تسجيل
دخول مربكة. هذه الأداة تضبط متغيّر بيئة واحدًا فقط، ولعملية ابن واحدة فقط.

---

## التثبيت

**المتطلبات:** أن يكون [Claude Code](https://claude.com/claude-code) مثبَّتًا
مسبقًا، وأن يكون لديك macOS/Linux مع bash، أو Windows مع PowerShell 5.1 أو أحدث.

### macOS و Linux

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.sh | bash
```

<div dir="rtl">

يثبّت `claude-account` في `~/.local/bin`، ويضيف هذا المسار إلى `PATH` إن لم يكن
موجودًا.

خيارات إضافية:

</div>

```bash
# مكان آخر للتثبيت
INSTALL_DIR=/usr/local/bin curl -fsSL .../install.sh | bash

# بدون تعديل أي ملف تهيئة للـ shell
NO_MODIFY_PATH=1 curl -fsSL .../install.sh | bash

# من نسخة محلية بدون تنزيل
git clone https://github.com/ebrahimelbarody74/claude-multi-account
cd claude-multi-account && ./install.sh
```

<div dir="rtl">

### Windows (PowerShell)

</div>

```powershell
irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.ps1 | iex
```

<div dir="rtl">

يثبّت في `%LOCALAPPDATA%\Programs\claude-multi-account` ويضيفه إلى `PATH` الخاص
بالمستخدم. لا يحتاج صلاحيات مسؤول. افتح نافذة طرفية جديدة بعد التثبيت.

إذا رفض PowerShell تشغيل السكربت، اسمح بالسكربتات المحلية لحسابك:

</div>

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

<div dir="rtl">

---

## الأوامر

| الأمر | ماذا يفعل |
| --- | --- |
| `claude-account add work` | ينشئ حساب `work` ويسجّل الدخول إليه |
| `claude-account add work --no-login` | ينشئه الآن، وتسجّل الدخول لاحقًا |
| `claude-account list` | كل الحسابات مع البريد والخطة وحالة الدخول |
| `claude-account work` | يشغّل Claude Code بهوية `work` |
| `claude-account use work` | الأمر نفسه بصيغة صريحة |
| `claude-account default` | يشغّل Claude Code العادي مع إلغاء `CLAUDE_CONFIG_DIR` |
| `claude-account status work` | البريد والخطة والمؤسسة وحالة الدخول لحساب واحد |
| `claude-account remove work` | يحذف الحساب المخزَّن (يسأل أولًا؛ `--yes` يتخطى السؤال) |
| `claude-account rename work company` | يعيد تسمية حساب مع الحفاظ على جلسته |
| `claude-account link work claude1` | ينشئ أمرًا مختصرًا: `claude1` يشغّل حساب `work` |
| `claude-account links` | يعرض قائمة المختصرات |
| `claude-account unlink claude1` | يحذف مختصرًا |
| `claude-account path work` | يطبع مجلد إعدادات الحساب |
| `claude-account env work` | يطبع سطر `export` لاستخدامه في سكربتاتك |
| `claude-account shell work` | يفتح shell فرعيًا موجَّهًا إلى `work` |
| `claude-account help` / `version` | المساعدة والإصدار |

كل ما يأتي بعد اسم الحساب يُمرَّر إلى `claude` كما هو دون تغيير:

</div>

```bash
claude-account work -p "summarise the README" --model opus
claude-account work mcp list
claude-account work auth status
```

<div dir="rtl">

---

## أمثلة

### macOS / Linux

</div>

```bash
# إعداد لمرة واحدة: حسابان ببريدين مختلفين
claude-account add work        # يفتح تدفّق تسجيل الدخول لبريد العمل
claude-account add personal    # يفتح تدفّق تسجيل الدخول للبريد الشخصي

# من هو من
claude-account list

# الاستخدام اليومي
cd ~/work/api    && claude-account work        # جلسة تفاعلية بهوية العمل
cd ~/side/blog   && claude-account personal    # جلسة تفاعلية بالهوية الشخصية

# أوامر مباشرة
claude-account work -p "explain this stack trace"
claude-account personal --model opus

# حسابك الأصلي كما هو
claude-account default

# البقاء على حساب واحد طوال جلسة الطرفية
claude-account shell work
#   ... كل استدعاء لـ claude داخل هذا الـ shell يستخدم حساب العمل ...
exit

# أو استخدامه داخل سكربتك، وبدون eval
export CLAUDE_CONFIG_DIR="$(claude-account path work)"
claude -p "run the work-account task"

# صيانة
claude-account status work
claude-account rename work company
claude-account remove personal
```

<div dir="rtl">

### أوامر أقصر

الأمر `link` يكتب ملفًا تنفيذيًا صغيرًا بجوار `claude-account`، فيعمل المختصر في
كل مكان — سكربتات، cron، أي shell — وليس في الجلسة التفاعلية فقط:

</div>

```bash
claude-account link work claude1
claude-account link personal claude2
claude-account link default claude0

claude1                       # جلسة على حساب العمل
claude1 -p "fix this test"    # الوسائط تُمرَّر كما هي
claude2 --model opus

claude-account links          # SHORTCUT  ACCOUNT
                              # claude1   work
                              # claude2   personal
claude-account unlink claude1
```

<div dir="rtl">

الـ alias يعمل أيضًا، لكن داخل shell تفاعلي من نوعه فقط:

</div>

```bash
alias cw='claude-account work'
```

<div dir="rtl">

> **الـ alias يتغلّب على المختصر.** لو كان `claude1` موجودًا أصلًا كـ `alias` في
> `~/.zshrc`، فالـ alias هو الذي ينفَّذ ولن يصل الأمر إلى المختصر. احذف الـ alias
> أولًا، ثم `hash -r`.

<div dir="rtl">

### Windows (PowerShell)

</div>

```powershell
# إعداد لمرة واحدة
claude-account add work
claude-account add personal

# من هو من
claude-account list

# الاستخدام اليومي
Set-Location C:\src\api ; claude-account work
Set-Location C:\src\blog; claude-account personal

# أوامر مباشرة
claude-account work -p "explain this stack trace"
claude-account personal --model opus

# حسابك الأصلي كما هو
claude-account default

# البقاء على حساب واحد طوال جلسة الطرفية
claude-account shell work
exit

# أو داخل سكربتك، وبدون Invoke-Expression
$env:CLAUDE_CONFIG_DIR = claude-account path work
claude -p "run the work-account task"

# صيانة
claude-account status work
claude-account rename work company
claude-account remove personal
```

<div dir="rtl">

### أوامر أقصر

</div>

```powershell
claude-account link work claude1
claude-account link personal claude2

claude1                       # جلسة على حساب العمل
claude1 -p "fix this test"    # الوسائط تُمرَّر كما هي

claude-account links
claude-account unlink claude1
```

<div dir="rtl">

الأمر `link` يكتب ملف `.cmd` بجوار `claude-account`، فيعمل من PowerShell ومن
`cmd.exe` على السواء. ودالة في `$PROFILE` تعمل أيضًا، داخل PowerShell فقط:

</div>

```powershell
function cw { claude-account work @args }
```

<div dir="rtl">

> **إذا ابتلع PowerShell أحد الخيارات.** يحلّل PowerShell أي `-something` قبل أن
> يصل إلى السكربت. الأمر `claude-account work -p "hi"` يعمل، لكن مع خيار غير
> معتاد يمكنك إيقاف التحليل بالرمز `--%`:

</div>

```powershell
claude-account work --% -p "hi" --model opus
```

<div dir="rtl">

---

## كيف يعمل

يقرأ Claude Code كامل حالته — بيانات الاعتماد والإعدادات وتهيئة MCP وسجل
المشاريع — من المجلد الذي يحدّده متغيّر البيئة `CLAUDE_CONFIG_DIR`، وقيمته
الافتراضية `~/.claude`.

إذن الحساب ما هو إلا مجلد:

</div>

```
~/.claude-accounts/            (0700)
├── work/                      → CLAUDE_CONFIG_DIR لحساب "work"
├── personal/                  → CLAUDE_CONFIG_DIR لحساب "personal"
└── client/                    → CLAUDE_CONFIG_DIR لحساب "client"
```

<div dir="rtl">

وعلى Windows تكون الشجرة نفسها في `%USERPROFILE%\.claude-accounts\`.

وتشغيل الحساب هو هذا بالضبط، ولا شيء غيره:

</div>

```bash
CLAUDE_CONFIG_DIR=~/.claude-accounts/work claude "$@"
```

<div dir="rtl">

ثلاث نقاط تستحق الانتباه:

- **`HOME` لا يُعدَّل أبدًا.** يظل Keychain على macOS يعمل بشكل طبيعي، فيتصرّف
  تسجيل الدخول تمامًا كما في تثبيت Claude Code عادي.
- **`default` اسم حساب محجوز وحقيقي.** يشغّل Claude Code مع **إزالة**
  `CLAUDE_CONFIG_DIR` صراحةً، فيكون هو تثبيتك الحالي في `~/.claude` — حتى لو كان
  الـ shell لديك قد صدّر ذلك المتغيّر مسبقًا.
- **لا يوجد ملف حالة لـ "الحساب الحالي".** يُختار الحساب لكل أمر على حدة، فيمكن
  لنافذتَي طرفية استخدام حسابين مختلفين في الوقت نفسه.

### متغيّرات البيئة

| المتغيّر | القيمة الافتراضية | المعنى |
| --- | --- | --- |
| `CLAUDE_ACCOUNTS_HOME` | `~/.claude-accounts` | مكان تخزين الحسابات |
| `CLAUDE_BIN` | `claude` | ملف Claude Code التنفيذي |
| `NO_COLOR` | غير مضبوط | اضبطه لتعطيل الألوان (bash) |

---

## الأمان

الأداة مصمَّمة لتكون مملّة عمدًا؛ فهي لا تخزّن شيئًا خاصًا بها.

- **لا توجد بيانات اعتماد داخل هذا المستودع، ولا تكتب الأداة أيًّا منها.**
  التوكِنات يتولّاها Claude Code بالكامل داخل مجلد إعدادات كل حساب (وعلى macOS
  داخل Keychain). الأداة لا تقرأها ولا تنسخها ولا تطبعها ولا ترسلها.
- **لا `eval`، ولا `Invoke-Expression`.** تُمرَّر الوسائط إلى `claude` كمصفوفة
  وسائط حقيقية (`exec env … claude "$@"` / `& claude @args`)، فلا يُعاد تحليل ما
  تكتبه كشيفرة shell. الأمر `claude-account env` **يطبع** سطر export فقط، ولا
  ينفّذه أبدًا.
- **اجتياز المسارات مُغلَق عند الاسم.** يجب أن يطابق اسم الحساب
  `^[A-Za-z0-9._-]+$`، ولا يبدأ بـ `.` أو `-`، ولا يكون `.` أو `..`، وبحدّ أقصى
  64 حرفًا. أما `../` و `/` و `\` و `~` والمسافات ورموز الـ shell وأسماء أجهزة
  Windows المحجوزة (`CON`, `NUL`, `LPT1` …) فكلها مرفوضة قبل بناء أي مسار.
- **الحذف محميّ مرتين.** يستخرج `remove` المجلد ثم يرفض ما لم يكن مجلده الأب هو
  جذر الحسابات بالضبط — ويرفض قطعًا `$HOME` و `~/.claude` وجذر الحسابات نفسه
  و `/`. كما يطلب تأكيدًا ما لم تمرّر `--yes`، ويرفض تمامًا إن لم تكن هناك طرفية
  تفاعلية ليسأل عبرها.
- **`~/.claude` لا يُكتب فيه ولا يُحذف أبدًا.** الطريقة الوحيدة التي تلمس بها
  الأداة تثبيتك الأصلي هي تشغيل `claude` بدون `CLAUDE_CONFIG_DIR`.
- **إزالة التثبيت لا تحذف الحسابات أبدًا.** يزيل المُزيل الملف التنفيذي ومدخل
  `PATH` فقط، ثم يطبع مكان حساباتك لتحذفها بنفسك إن أردت.
- **تُنشأ مجلدات الحسابات بصلاحيات `0700`** (للمالك فقط) على macOS و Linux.
- **المختصرات لا يمكنها اختطاف أمر قائم.** يرفض `link` الأسماء المحجوزة — وعلى
  رأسها `claude`، لأن مختصرًا بهذا الاسم سيستدعي نفسه إلى ما لا نهاية — ويرفض
  الكتابة فوق أي ملف لم يُنشئه، ويرفض اسمًا يشير أصلًا إلى أمر آخر في `PATH`.
  و`unlink` لا يحذف إلا الملفات التي تحمل علامته.

وحالات المدخلات العدائية أعلاه مغطّاة في مجموعتَي الاختبارات؛ انظر
[`tests/`](tests/).

---

## حل المشكلات

**`claude-account: command not found` بعد التثبيت مباشرة.**
مجلد التثبيت ليس ضمن `PATH` في هذه الجلسة. افتح طرفية جديدة، أو نفّذ
`export PATH="$HOME/.local/bin:$PATH"` (في PowerShell: افتح طرفية جديدة — فقد
حُدِّث `PATH` الخاص بالمستخدم).

**`'claude' was not found on PATH`.**
ثبّت Claude Code أولًا: <https://claude.com/claude-code>. وإن كان في مسار غير
معتاد، أشِر إليه: `CLAUDE_BIN=/opt/claude/bin/claude claude-account list`.

**`list` يُظهر حسابًا بحالة `logged out`.**
انتهت صلاحية جلسة ذلك الحساب أو لم تُنشأ أصلًا. سجّل الدخول مجددًا عبر
`claude-account <name>` وسيطلب منك ذلك.

**حسابان يظهران بالبريد نفسه.**
سجّلت الدخول في كليهما بالعنوان نفسه. احذف أحدهما
(`claude-account remove <name>`) وأعِد إضافته بالبريد الآخر.

**PowerShell: "cannot be loaded because running scripts is disabled".**
نفّذ `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. علمًا أن ملف `.cmd`
المثبَّت يمرّر `-ExecutionPolicy Bypass` أصلًا، فالمشكلة تظهر عادةً فقط عند
تشغيل `claude-account.ps1` مباشرة.

**PowerShell: أحد الخيارات يُبتلع.**
استخدم رمز إيقاف التحليل: `claude-account work --% -p "hi"`.

**المختصر يشغّل الحساب الخطأ.**
الـ alias الذي يحمل الاسم نفسه له الأولوية على المختصر. تحقّق بـ
`type claude1` (zsh/bash) أو `Get-Command claude1` (PowerShell)؛ فإن ظهر أنه
alias، احذفه من `~/.zshrc` أو `$PROFILE`.

**أريد أن أرى بالضبط ما سيُنفَّذ.**
`claude-account path work` يطبع المجلد؛ والأمر دائمًا هو
`CLAUDE_CONFIG_DIR=<ذلك المجلد> claude <وسائطك>`.

---

## إزالة التثبيت

كلا المُزيلَين يزيلان الأداة ويتركان كل حساب مسجَّل الدخول وسليمًا.

**macOS / Linux**

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.sh | bash
```

<div dir="rtl">

**Windows**

</div>

```powershell
irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.ps1 | iex
```

<div dir="rtl">

ولحذف الحسابات المخزَّنة أيضًا — وهذا يُخرج تلك الحسابات نهائيًا:

</div>

```bash
rm -rf ~/.claude-accounts                                         # macOS / Linux
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude-accounts"   # Windows
```

<div dir="rtl">

---

## التطوير

</div>

```bash
./tests/run-tests.sh            # مجموعة اختبارات bash
pwsh -File tests/run-tests.ps1  # مجموعة اختبارات PowerShell
```

<div dir="rtl">

تعمل المجموعتان على مجلد حسابات مؤقت وملف `claude` تنفيذي وهمي، فلا تلمسان
حساباتك الحقيقية ولا تتصلان بالشبكة.

---

## الرخصة

[MIT](LICENSE).

هذا المشروع غير تابع لشركة Anthropic. و"Claude" و"Claude Code" علامتان تجاريتان
لشركة Anthropic, PBC.

</div>
