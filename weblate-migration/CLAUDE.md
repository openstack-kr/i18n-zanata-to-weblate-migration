# CLAUDE.md

이 폴더(`weblate-migration/`)에서 작업할 때 따라야 할 규칙.

## 배경

`openstack-weblate-migration` 저장소(Zanata → Weblate 번역 리소스
마이그레이션 도구)의 스크립트를 스텝 번호가 붙은 폴더 구조
(`common/`, `01-setup-env/` ~ `05-test-accuracy/`)로 재정리하는
작업을 여기서 진행한다. 원본 저장소는 백업 겸 롤백 지점으로 그대로
남겨두고, 재정리는 전부 이 폴더(같은 저장소의 `weblate-migration/`)
안에서 이뤄진다 — 재정리 대상 파일은 원본에서 `.git/`을 제외하고
복사해 온 사본이다.

재정리 전략의 근거(어떤 폴더 순서로 나눌지, 왜 그렇게 나눴는지, 어떤
파일이 죽은 코드인지 등)는 이 저장소 밖, 로컬에만 있는
`~/claude-docs/weblate-migration/pipeline-step-folder-layout/folder-arrangement.md`에
있다. 바로 옆의 `language/` 폴더는 완전히 다른 목적(Weblate 언어
설정을 Zanata와 동기화하는 도구)의 기존 코드이므로, 이 작업에서
건드리지 않는다.

## 문서 구조

`openstack-weblate-migration/CLAUDE.md`가 쓰던 것과 같은 관행을
그대로 따른다 — **이 저장소에도 계획 문서(plan.md 같은)를 두지
않는다.** 이 작업의 진단/계획/실행 기록은 전부
`~/claude-docs/weblate-migration/pipeline-step-folder-layout/`
아래에 로컬로만 둔다 (별도 저장소라고 새 문서 트리를 만들지 않고,
같은 goal 폴더를 계속 쓴다):

```
~/claude-docs/weblate-migration/pipeline-step-folder-layout/
  folder-arrangement.md   # 전체 재정리 전략과 근거 ("왜") — 이미 있음
  goal.md                 # Phase별 진행 상태 트래커 — 이미 있음
  phase-N-<slug>.md        # Phase 하나의 계획 + 실행 기록 (아래 "작업 절차" 참고)
```

### `phase-N-<slug>.md`의 구조

Phase 하나당 문서 하나, 그 안에 아래 4개 섹션을 이 순서로 둔다. 앞
"계획" 섹션은 구현을 시작하기 *전에*, 나머지 세 섹션은 구현·테스트가
*끝난 뒤에* 채운다 — 계획을 사후에 실행 내용에 맞춰 고쳐 쓰지 않는다
(계획은 계획대로, 실제로 무슨 일이 있었는지는 별도 섹션에 남긴다).

1. **## 계획** — 이 Phase에서 옮길 파일/폴더, 같이 고쳐야 할 참조
   목록(`folder-arrangement.md`의 해당 Phase 몫), 예상 위험.
2. **## 실행 절차** — 실제로 수행한 작업을 순서대로 기록: 어떤 명령으로
   옮겼는지(`git mv` 등), 어떤 파일의 어떤 줄을 어떻게 고쳤는지. 계획과
   다르게 진행된 부분이 있으면 무엇이 왜 달라졌는지 여기 적는다.
3. **## 실행 결과** — 5단계 "테스트"의 각 체크리스트 항목(`bash -n`,
   `grep -rn "<옛 폴더명>/"`, 실제 파이프라인 실행, flake8/py_compile)의
   pass/fail을 항목별로 구체적으로 남긴다. "테스트함" 한 줄이 아니라
   실제로 돌린 명령과 결과를 남긴다.
4. **## 특이사항** — 계획과 다르게 진행된 이유, 작업 중 예상치 못하게
   발견한 문제, 이번 Phase 범위 밖이라 다음 Phase나 별도 이슈로 미룬
   것, 다음 Phase에 영향을 주는 내용. 특이사항이 없어도 섹션 자체를
   생략하지 않고 "없음"이라고 명시한다 — 나중에 다시 볼 때 "확인을
   안 한 건지 정말 없었던 건지" 구분할 수 있게 하기 위함.

## 작업 절차 (Phase 하나당)

Phase 번호와 순서는 `folder-arrangement.md`의 "실행 전략" 절
(Phase 0 백업 복사 → Phase 1 `pretty-printer.sh`를 `common/`으로 →
Phase 2 `01-setup-env/` → Phase 3 `02-03` → Phase 4 `04-05`)을 따른다.
`migration/`의 나머지 레거시 파일은 건드리지 않기로 결정했으므로
(결정 사항 1번) 별도 Phase가 없다 — Phase 4가 마지막이다.

1. **브랜치**: Phase마다 `develop`에서 분기한 `phase-N-<slug>` 브랜치를
   새로 만들어 그 안에서만 작업한다. PR의 base는 항상 `develop`이고,
   승인되면 `develop`에 머지한다 (`main`이 아님 — 확인됨).
2. **계획 먼저 작성**: 코드를 건드리기 전에
   `~/claude-docs/weblate-migration/pipeline-step-folder-layout/phase-N-<slug>.md`를
   만들고 "계획" 섹션부터 채운다 — 이 Phase에서 옮길 파일, 같이 고쳐야
   할 참조(`folder-arrangement.md`의 "폴더 이동 시 함께 고쳐야 하는
   참조" 표 참고), 예상 위험. 이 섹션을 다 쓴 다음에 그 계획대로
   구현을 시작한다.
3. **범위**: 해당 Phase가 다루는 이동/rename만 한다. 작업 중 범위 밖
   문제(예: 코드 자체의 버그)를 발견하면 그 자리에서 고치지 않고
   `folder-arrangement.md`나 새 Phase 계획에 남겨둔다.
4. **구현**: 폴더/파일을 옮기는 커밋과 그걸 참조하는 경로를 고치는
   커밋은 분리하지 않는다 — 같은 Phase 안에서 항상 같이 끝낸다.
   `folder-arrangement.md`의 "실행 전략"이 Phase별로 "이동"과 "참조
   갱신"을 쌍으로 나열해 두었으니 그 목록을 그대로 체크리스트로 쓴다.
   가장 놓치기 쉬운 건 **self-reference**다: 옮긴 파일 자신이 옛
   경로로 자기 자신이나 같은 폴더의 다른 파일을 가리키는 줄 (예:
   `get_zanata_xml.sh`가 `$SCRIPTSDIR/prepare_translations/create_zanata_xml.py`를
   부르는 것). 폴더를 옮기면 이 줄도 새 폴더명으로 같이 바뀌어야
   한다 — `bash -n`은 이런 잘못된 경로를 잡아내지 못하므로(문법은
   멀쩡함), 5단계의 `grep`과 실제 실행 확인이 특히 중요하다.
   (`common/`은 이름을 바꾸지 않기로 결정했기 때문에(결정 사항 2번),
   "아직 안 옮긴 폴더 안에서 `common/...`을 참조하는 파일도 미리
   고쳐야 하는" 경우는 이번 Phase들에는 없다 — `folder-arrangement.md`의
   "폴더 이동 시 함께 고쳐야 하는 참조" 표에서 "수정 불필요"로 표시된
   항목들이 그래서 없는 것이다.)
5. **테스트**: 구현 후 최소한 아래를 직접 실행해서 확인한다 (이
   저장소에도 자동 테스트가 없다).
   - 옮기거나 수정한 모든 `.sh` 파일에 `bash -n`.
   - `grep -rn "<옛 폴더명>/"`로 저장소 전체를 훑어 갱신 안 된 참조가
     남아있지 않은지 확인 (0건이어야 함).
   - 가능하면 실제 프로젝트 하나로 파이프라인을 처음부터 끝까지 한 번
     돌려서 이전과 동일하게 동작하는지 확인한다.
   - Python 변경이 있다면 `~/workspace/.venv`의 `flake8`/`py_compile`로
     검증한다 (원본 저장소 `CLAUDE.md`와 동일한 venv).
6. **문서화**: 구현·테스트가 끝나면 커밋/PR 여부를 묻기 *전에*
   `phase-N-<slug>.md`의 "실행 절차"·"실행 결과"·"특이사항" 세 섹션을
   채운다 (구조는 위 "`phase-N-<slug>.md`의 구조" 절 참고). 그 다음
   `goal.md`의 Phase 상태 표를 갱신한다. 커밋/PR 여부와 상관없이(7단계
   에서 사용자가 "이대로 둘까요"를 택하더라도) 이 문서화는 항상
   먼저 끝내 둔다 — 사용자가 7단계에서 판단할 때 "무엇을 했고 어떻게
   검증했는지"를 이미 문서로 보여줄 수 있어야 한다.
7. **커밋/PR 여부는 반드시 사용자에게 먼저 확인한다** — 이게 원본
   저장소 `CLAUDE.md`와 가장 다른 부분이다:
   - 테스트를 통과했다고 해서 자동으로 커밋하거나 PR을 열지 않는다.
   - 6단계 문서화가 끝나면 무엇이 바뀌었고 어떻게 검증했는지 요약해서
     사용자에게 보여주고, **"커밋할까요, PR을 열까요, 아니면 이대로
     둘까요?"를 명시적으로 물어본다.**
   - 자동 머지 권한은 없다 — PR을 열었더라도 머지는 항상 사용자
     확인 후에만 한다.
8. **PR**: 사용자가 PR을 원하면 `git push -u origin phase-N-<slug>` 후
   `gh pr create --base develop --head phase-N-<slug>`로 연다 (base는
   항상 `develop`). PR 본문에 요약, 테스트 내역(체크리스트), 결과
   문서 경로를 적는다.
9. **머지**: PR을 올렸다고 자동으로 머지하지 않는다. 사용자가 머지를
   명시적으로 요청하면 그때 `gh pr merge --merge --delete-branch`로
   `develop`에 머지하고 브랜치를 지운다. 머지 후에는 로컬 `develop`을
   `git pull`로 갱신하고, `git fetch --prune`으로 지워진 원격 브랜치의
   로컬 잔여 참조를 정리한다.

## 커밋 메시지 컨벤션

이 저장소 최근 커밋이 이미 Conventional Commits 스타일을 쓰고 있다
(`fix: WeblateRestService에 POST 메서드 추가`, `feat: Add language
migration` — `git log --oneline` 확인함). 이번 재정리 작업도 같은
형식을 따른다.

- 형식: `<type>: <한 줄 요약>` (한글, 끝에 마침표 없음). Phase를
  구분하고 싶으면 스코프를 붙여 `<type>(phase-N): <요약>`.
- type: 이번 작업은 전부 동작 변경이 없는 순수 구조 개편(폴더 이동 +
  참조 경로 갱신)이므로 항상 **`refactor`**를 쓴다 — `fix`/`feat`은
  버그 수정·기능 추가용이라 이 작업 성격과 안 맞는다.
- 예시:
  - `refactor(phase-1): pretty-printer.sh를 migration/에서 common/으로 이동`
  - `refactor(phase-2): setup_env/를 01-setup-env/로 이동하고 참조 경로 갱신`
- PR 제목도 같은 컨벤션을 따른다.
- `~/claude-docs/...` 아래 계획/결과 문서는 이 저장소 밖에 있어 이
  저장소의 커밋에 포함되지 않으므로, 이 컨벤션 대상이 아니다.

## 환경 메모

- GitHub CLI(`gh`)는 계정 `S0okJu`로 인증되어 있다 (원본 저장소와 동일).
- origin: `https://github.com/openstack-kr/i18n-zanata-to-weblate-migration.git`.
  원격에는 `main`, `develop`이 있다. 로컬은 현재 `develop`을 체크아웃한
  상태다.
- 이 저장소에는 이번 작업과 무관한, 이미 있던 커밋되지 않은 로컬
  변경이 있다 (`LICENSE`, `language/__pycache__/weblate_utils.cpython-310.pyc`
  수정, untracked `.gitignore`). `git status`로 스테이징 전에 항상
  확인하고, 이 파일들은 절대 같이 커밋하지 않는다.
- `language/` 폴더는 이 작업과 무관한 별도 도구이므로 건드리지 않는다.
- 재정리 대상 코드(파이프라인 스크립트) 자체의 동작·버그에 대한 배경은
  `openstack-weblate-migration/CLAUDE.md`와 그 저장소의
  `~/claude-docs/weblate-migration/` 아래 다른 goal 문서들을 참고한다.
  이 문서는 "재정리 작업 방식"만 다룬다.
