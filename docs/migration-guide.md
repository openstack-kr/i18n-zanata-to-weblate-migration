# Zanata → Weblate 마이그레이션 가이드 (초보자용)

이 문서는 `weblate-migration/` 도구를 처음 사용하는 사람을 위한 안내서입니다.
용어를 하나씩 풀어서 설명하므로, OpenStack 번역이나 gettext(PO/POT)에
익숙하지 않아도 따라올 수 있습니다.

## 1. 이 도구가 하는 일

OpenStack I18n(국제화) 팀은 그동안 **Zanata**라는 번역 플랫폼을 써왔습니다.
Zanata는 2018년 8월부터 개발이 중단되었기 때문에, 팀은 번역 데이터를
**Weblate**라는 새 플랫폼으로 옮기고 있습니다. 이 저장소의 `weblate-migration/`
폴더가 그 이관 작업을 자동화하는 도구입니다.

핵심 목표는 **기존 번역 내용과 형식을 최대한 그대로 보존**하는 것입니다.
즉 Zanata에 있던 번역문, 문맥 정보, 복수형(plural) 구조 등이 Weblate로
옮겨간 뒤에도 동일해야 합니다.

### 알아두면 좋은 용어

| 용어 | 의미 |
|---|---|
| PO 파일 | 실제 번역문이 들어있는 파일 (`.po`). 로케일(언어)마다 하나씩 있습니다. |
| POT 파일 | 번역되지 않은 원문 템플릿 (`.pot`). 여기서 각 언어의 PO 파일이 만들어집니다. |
| 컴포넌트(component) | Weblate에서 번역 단위를 묶는 그룹. 보통 프로젝트의 모듈 하나에 대응합니다 (예: `openstack-dashboard-django`). |
| 로케일(locale) | 언어/지역 코드 (예: `ko`, `de`, `zh_TW`). |
| fuzzy | "번역은 있지만 재검토가 필요한 상태"를 뜻하는 gettext 표시. |

## 2. 시작하기 전에 준비할 것

아래 항목이 없으면 마이그레이션 스크립트가 중간에 실패합니다. 순서대로
확인하세요.

1. **Python 3, pip, git**이 설치되어 있어야 합니다.
2. **zanata-cli**가 설치되어 있고, `~/.config/zanata.ini`에 Zanata 접속
   정보가 설정되어 있어야 합니다.
   (`01-setup-env/setup.sh`의 `check_zanata_cli()`가 이 두 가지를 확인합니다.)
3. **Weblate 접속 정보**를 환경 변수로 설정해야 합니다.

   ```bash
   export WEBLATE_URL="https://your-weblate-instance.example.com"
   export WEBLATE_TOKEN="발급받은 API 토큰"
   ```

   이 값이 없거나 예시값(`<weblate_url>`, `<weblate_token>`) 그대로면
   스크립트가 바로 에러를 내고 멈춥니다.
4. `gettext`, `jq` 같은 시스템 패키지가 필요합니다. 이 패키지들은
   `01-setup-env/bindep.txt`에 정의되어 있고, 스크립트가 실행되며
   `sudo apt install`로 자동 설치를 시도합니다 (sudo 권한이 필요합니다).

> 위 1~4번은 한 번만 설정하면 됩니다. 이후에는 매번 다시 설정할 필요가
> 없습니다 (단, 새 워크스테이션에서 처음 실행할 때는 다시 필요합니다).

## 3. 두 가지 실행 방법

이 도구는 프로젝트 하나만 옮길 수도 있고, 여러 프로젝트를 한 번에 옮길
수도 있습니다.

### 방법 A. 프로젝트 하나만 마이그레이션

```bash
cd weblate-migration
./migration_resources.sh <project_name> <version> <workspace_name>
```

| 인자 | 설명 | 예시 |
|---|---|---|
| `project_name` | 이관할 OpenStack 프로젝트 이름 (필수) | `horizon` |
| `version` | 브랜치/버전 이름 (생략 시 `master`) | `stable/2025.1` |
| `workspace_name` | 작업 폴더 이름 (생략 시 `workspace`, 홈 디렉터리 아래 생성) | `my-workspace` |

예시:

```bash
./migration_resources.sh horizon stable/2025.1 workspace
```

### 방법 B. 여러 프로젝트를 한 번에 마이그레이션(배치)

여러 프로젝트 × 여러 버전을 순서대로 처리하고 싶을 때 씁니다.

```bash
cd weblate-migration
./migration_projects.sh <project_list.txt> <version_list.txt>
```

`list.txt`에 프로젝트 이름을 한 줄씩 적습니다.

```text
horizon
designate-dashboard
freezer-web-ui
```

`version.txt`에 버전(브랜치) 이름을 한 줄씩 적습니다.

```text
master
stable/2025.2
```

이렇게 하면 **(프로젝트 수) × (버전 수)** 만큼의 조합이 순서대로
처리됩니다. 예를 들어 프로젝트 3개, 버전 2개면 총 6번 실행됩니다.
이 저장소의 `weblate-migration/list.txt`, `version.txt`가 실제 예시
파일이니 참고하세요.

이 배치 스크립트는 실행 중 아래와 같은 진행 상황을 보여줍니다.

```
[2/6] (33%) 처리 중: 'horizon' (버전: stable/2025.1) (예상 남은 시간: 12분 30초)
horizon / stable/2025.1  ⏳ 진행중
```

한 조합이 끝날 때마다 15초씩 쉬었다가 다음 조합으로 넘어갑니다
(Weblate/Zanata 서버에 부담을 주지 않기 위한 대기 시간입니다).

## 4. 내부적으로 어떤 일이 일어나는가 (5단계)

`migration_resources.sh` 하나를 실행하면 아래 5단계가 순서대로 진행됩니다.
콘솔에는 각 단계가 시작할 때 `⏳`, 끝나면 `✓`(성공) 또는 `✗`(실패)로 표시됩니다.

```
1단계 환경설정 → 2단계 클론 → 3단계 POT 생성 → 4단계 컴포넌트 생성 → 5단계 정확도 테스트
```

| 단계 | 폴더 | 하는 일 |
|---|---|---|
| 1. 환경설정 | `01-setup-env/` | 파이썬 가상환경(venv) 생성, 의존성 설치, 작업 폴더(workspace) 준비 |
| 2. 번역 준비 | `02-prepare-translations/` | 프로젝트 저장소를 클론하고, `zanata.xml`을 만들어 Zanata에서 기존 번역(PO)을 내려받음 |
| 3. 컴포넌트 이름 파악 | `03-prepare-component-name/` | 클론한 프로젝트 안에서 Weblate 컴포넌트로 만들 모듈 이름들을 자동으로 찾아냄 |
| 4. Weblate 컴포넌트 생성 | `04-prepare-weblate-components/` | Weblate에 프로젝트/카테고리/컴포넌트를 만들고, 로케일별 번역 파일을 업로드 |
| 5. 정확도 테스트 | `05-test-accuracy/` | 업로드된 Weblate 번역을 Zanata 원본과 비교해 손실 여부를 검증 |

즉, **1~3단계는 "옮길 준비"**, **4단계는 "실제로 옮기기"**,
**5단계는 "제대로 옮겨졌는지 확인하기"**라고 이해하면 됩니다.

## 5. 결과 확인하기: 로그와 리포트

### 로그 파일

실행할 때마다 `weblate-migration/logs/` 아래에 프로젝트별 로그가 쌓입니다.

```text
logs/
└── <project_name>/
    ├── project.<타임스탬프>.log   # 전체 진행 로그
    └── error.<타임스탬프>.log     # 에러만 모아놓은 로그
```

로그 한 줄은 이런 형식입니다.

```
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] Testing locale: mai
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] ✓ Count matched(translated/total): 73/177
```

`프로젝트 | 버전 | 컴포넌트 | 로케일 | 메시지` 순서입니다. 컴포넌트/로케일이
아직 정해지지 않은 초반 단계(클론, POT 생성 등)의 로그는 그 자리에
`-`가 표시됩니다.

무언가 실패했다면, 먼저 **`error.*.log`**부터 열어보세요. 전체 로그를
뒤질 필요 없이 실패 원인만 모여 있습니다.

### 요약 리포트

배치 실행(`migration_projects.sh`)이 모두 끝나면, 콘솔에 프로젝트 ×
버전 × 컴포넌트 × 로케일 상태를 정리한 표가 출력되고, 같은 내용이
`report.md` 파일로도 저장됩니다. 매번 `logs/` 안의 에러 로그를 일일이
열어보지 않아도 결과를 한눈에 파악할 수 있습니다.

## 6. "정확도 테스트"가 실패했다면

5단계(정확도 테스트)는 Zanata 원본과 Weblate 결과를 비교해서 아래를
확인합니다.

- 번역된 문장 수가 같은가 (`Count matched`)
- 번역 문장 내용(`msgid`/`msgstr`)이 실제로 같은가 (`Sentence detail matched`)

이 테스트가 실패하는 대표적인 원인은 이미 `docs/horizon-test.md`에
정리되어 있습니다. 요약하면:

- 일부 로케일의 번역이 아예 반영되지 않고 빈 파일로 남는 경우
- 원문 그대로 옮기는 대신 "번역문만 채워 넣는" 업로드 방식(`method=translate`)
  때문에 fuzzy 표시나 plural(복수형) 구조가 사라지는 경우

정확도 테스트를 더 엄밀하게 만드는 방법(msgctxt 검증, plural index
비교, fuzzy 분류 강화)은 `docs/enhance-migration-accuracy.md`에 정리되어
있으니, 검증 로직을 손보고 싶다면 그 문서를 먼저 읽어보세요.

## 7. 자주 겪는 문제

| 증상 | 원인 | 해결 방법 |
|---|---|---|
| `[ERROR] WEBLATE_URL is not set` | 환경 변수 미설정 | `export WEBLATE_URL=...`, `export WEBLATE_TOKEN=...` 실행 후 재시도 |
| `[ERROR] zanata-cli is not installed` | zanata-cli 미설치 | zanata-cli 설치 후 `~/.config/zanata.ini` 존재 확인 |
| `[ERROR] Failed to install requirements.txt in venv` | pip 설치 실패 | 네트워크/권한 확인, `01-setup-env/requirements.txt` 확인 |
| `sudo apt install` 단계에서 멈춤 | bindep 패키지 설치 중 sudo 비밀번호 대기 | 스크립트를 sudo 비밀번호 입력이 가능한 터미널에서 실행 |
| 특정 로케일만 번역이 전부 비어 있음 | 업로드 실패 또는 자동 생성 파일로 덮어써짐 | `docs/horizon-test.md`의 "번역 전체 미반영" 사례 참고 |

## 8. 요약 체크리스트

- [ ] Python 3 / git 설치 확인
- [ ] zanata-cli 설치 + `~/.config/zanata.ini` 확인
- [ ] `WEBLATE_URL`, `WEBLATE_TOKEN` 환경 변수 설정
- [ ] (여러 프로젝트라면) `list.txt`, `version.txt` 준비
- [ ] `./migration_resources.sh` 또는 `./migration_projects.sh` 실행
- [ ] 실행 중 콘솔의 `⏳`/`✓`/`✗` 표시로 단계별 진행 확인
- [ ] 완료 후 `logs/`와 `report.md`에서 실패한 항목이 있는지 확인
- [ ] 실패가 있다면 `docs/horizon-test.md`의 원인 유형과 비교

## 참고 문서

- `weblate-migration/README.md` — 폴더 구조와 워크스페이스 레이아웃 원문(영문)
- `docs/horizon-test.md` — 실제 마이그레이션 실패 사례와 원인 분석
- `docs/enhance-migration-accuracy.md` — 정확도 테스트(5단계) 개선 방향
