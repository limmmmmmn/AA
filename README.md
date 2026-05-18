# Appears! Appears! — 제작 README

> **이 문서는 클로드코드(클코)에게 전달하는 *제작 헌법*이다.**
> **모든 코딩 결정은 이 문서를 따른다.**
>
> 최초 작성: 2026년 5월 / 강원도 작업 시작
> 비전 재설정: 2026-05-18 (인크리멘탈로 피봇)

---

## ⚡ 게임 한 줄

> **세계가 한 칸씩 펼쳐지는 인크리멘탈. 10초짜리 런을 반복하면서, "언폴드"로 메커니즘을 하나씩 켜 나간다.**

```
한 런 = 짧다 (시작 10초, 해금할수록 늘어남)
런 끝 → 언폴드 패널 → 골드로 노드 해금 → 다음 런
런을 거듭하면서:
  - 처음엔 움직임만
  - 골드 등장 → 검 등장 → 몬스터 등장 → 자동 전투 → 멀티 전투창 ...
  - 빈 칸이 한 칸씩 채워진다
```

**후크:** 인크리멘탈인데 *세계가 시각적으로 펼쳐진다.*
숫자만 올라가는 게 아니라, 필드 위에 실제로 새 것들이 *appear*한다.

---

## 🎯 장르 — 인크리멘탈

paperpilot의 *Defining the Genre* 정의 기준:

| 인크리멘탈 핵심 특성 | 이 게임에서 어떻게 |
|---|---|
| **Unfolding mechanics** (메커니즘이 진행되면서 점진적으로 열림) | 게임의 정체성 그 자체. "언폴드" 버튼, 스킬 트리의 빈 칸이 채워짐 |
| **Reduced consequences** (페일 스테이트 없음) | 타이머가 0이면 자동 클리어. 죽거나 진다는 개념 없음 |
| **Optimization problems** | 어느 노드를 먼저 살지 = 빌드 결정 |
| **Resource management** | 골드 → 노드 해금. 늘어날 수 있음 (HP/MP/장비 등) |

**참고:** https://paperpilot.dev/garden/guide-to-incrementals/defining-the-genre

**우리만의 변주:**
- 클래식 인크리멘탈의 "Pure UI" 인터페이스 대신 **작은 픽셀 세계**가 캔버스다.
- 노드 해금 = UI 토글이 아니라 *세계 안에 새 사물이 등장*한다.

---

## 🔧 기술 스택

```
엔진: Godot 4.6
해상도: 640 × 360 (절대 흔들지 마)
언어: GDScript
버전 관리: Git
배포: Steam (장기 목표)
```

---

## 🧩 현재 작동하는 시스템 (실제 코드 기준)

### **루프**

```
1. Stage 시작 (scenes/stages/stage_01.tscn)
2. 카운트다운 = 10초 + RunState.timer_bonus_seconds
3. 시간 동안:
   - 필드 위에서 히어로 이동 (해금된 스킬에 따라)
   - 픽업/적/장비와 상호작용 (해금된 만큼)
4. 시간 0 → "게임 클리어!" → 결과 패널
5. [언폴드] → 스킬 트리 → 골드로 노드 해금 → 노드 1개당 영구 +1초
6. [계속] → 씬 리로드 (RunState는 유지)
```

### **상태 (오토로드 = RunState 하나)**

`scripts/autoload/run_state.gd`

```gdscript
gold: int
hero_base_attack: int = 2
hero_attack_bonus: int        # 검 줍기 등으로 증가
sword_collected: bool
timer_bonus_seconds: int      # 해금 노드 수만큼 누적
unlocked: Dictionary          # skill_id → bool
```

**시그널:** `gold_changed`, `skill_unlocked`, `hero_attack_changed`

### **스킬 트리 (.tres 노드)**

`data/skill_nodes/` — 각 노드는 `SkillNodeData` 리소스
필드: `grid: Vector2i`, `skill_id: StringName`, `skill_name`, `description`, `cost`, `hidden`

현재 노드:

| id | 좌표 | 비용 | 효과 |
|---|---|---|---|
| (root) | (0,0) | — | 트리의 중심 |
| `gold` | (시작 해금) | — | 골드 픽업 표시/수집 |
| `movement` | (시작 해금) | — | 히어로 이동 |
| `item` | (-2, 0) | 6 | 필드에 검 등장 (줍기 → +2 공격) |
| `spawner` | (0, -2) | 12 | 몬스터 자동 리스폰 |
| `monster` | (0, -3) | 12 | (hidden, 미사용) |
| `auto_battle` | (0, 2) | 48 | 전투창 자동 전투 |
| `battle_movement` | (0, 3) | 96 | 전투 중에도 필드 이동 가능 |
| `multi_battle` | (0, 4) | 192 | 전투창 여러 개 동시 |

**그리드 시스템:** 사방으로 펼쳐짐. 해금 시 인접 노드가 동적으로 spawn.
빈 칸은 "???" 로 표시되어 *다음 노드가 들어설 자리*임을 보여줌.

### **필드 (`scripts/stages/unfold_field.gd`)**

```
- 작은 녹색 사각 (224, 116) ~ (416, 244)
- 히어로 = 픽셀 캐릭터, WASD/방향키 이동 (연속)
- 픽업: GoldPickup, SwordPickup
- 적: SlimeMarker (방랑 + 충돌 시 전투 트리거)
- multi_battle 해금 전엔 적과 충돌 시 적이 밀려나고 "?" 표시
```

### **전투창 (`scripts/ui/battle_view.gd`)**

```
- 1인칭 드퀘 톤 (검정 배경 + 흰 테두리)
- 좌측: 스테이터스 패널, 우측: 명령 메뉴 (Fight/Spell/Run/Item)
- HP 시스템, 데미지 로그
- auto_battle 해금 시 명령 입력 없이 자동
- multi_battle 해금 시 같은 view를 여러 개 인스턴스
```

---

## 🏗️ Godot 4 제작 원칙 (반드시 지킬 것)

### **원칙 1: 씬 + 노드 우선, 코드 마지막**

```
❌ 나쁨: 코드로 노드 생성
✅ 좋음: 씬에서 노드 배치, 코드는 행동만
```

### **원칙 2: 시그널로 디커플링**

```
❌ 나쁨: get_node("/root/...") 직접 참조
✅ 좋음: signal emit → 인스펙터 또는 .connect()
```

**연결 방식:**
- **에디터 연결**: 정적 관계 → *우선 선택*
- **코드 연결**: 동적 관계 (인스턴스 생성 시)만

### **원칙 3: 오토로드 최소화**

현재 RunState 하나뿐. 늘릴 때는 신중히.

```
✅ 허용 가능:
- RunState: 런 영속 상태 (현재)
- (필요 시) EventBus: 전역 시그널
- (필요 시) AudioManager: 효과음/BGM

❌ 피할 것:
- 데이터 + 로직 섞기
- 한 씬에서 끝낼 수 있는 걸 오토로드로
```

### **원칙 4: Resource 활용 (데이터 = .tres)**

스킬 노드는 이미 이렇게 되어 있음.
새 데이터 (예: 새 적, 새 아이템) 추가할 때도 *코드 1줄, .tres N개* 원칙 유지.

```
data/
├── enemies/
│   └── slime.tres
└── skill_nodes/
    ├── root.tres
    ├── item.tres
    └── ... (각 노드)
```

### **원칙 5: @export로 인스펙터 노출**

```
✅ @export var move_speed: float = 100.0
❌ const MOVE_SPEED = 100.0
```

인스펙터에서 빠른 밸런싱. 코드 수정 X.

### **원칙 6: @onready로 노드 참조**

```
@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = %HPBar  # 고유 이름
```

### **원칙 7: 시그널 매개변수 명시**

```
✅ signal enemy_defeated(enemy: Node, gold: int)
❌ signal enemy_defeated
```

---

## 📁 프로젝트 구조 (현재 상태)

```
project_root/
├── project.godot              # 진입점 = scenes/stages/stage_01.tscn
├── README.md                  # 이 문서
│
├── scenes/
│   ├── stages/
│   │   └── stage_01.tscn      # 메인 스테이지 (Field + UI + BattleView)
│   ├── entities/
│   │   ├── hero.tscn
│   │   ├── slime_marker.tscn
│   │   ├── gold_pickup.tscn
│   │   └── sword_pickup.tscn
│   ├── ui/
│   │   ├── battle_view.tscn
│   │   ├── skill_node.tscn
│   │   ├── skill_tree_panel.tscn
│   │   ├── level_up_*.tscn
│   │   ├── equip_slot.tscn
│   │   └── stat_bar.tscn
│   ├── objects/
│   │   ├── field_campfire.tscn
│   │   ├── field_recovery_orb.tscn
│   │   └── field_shrine.tscn
│   ├── main.tscn / battle_window.tscn / event_window.tscn /
│   │   home_base.tscn / manual_battle.tscn / player.tscn
│   │   (※ 옛 프로토타입 잔재 — 정리 대상)
│
├── scripts/
│   ├── autoload/
│   │   ├── run_state.gd       # ✅ 현재 사용 중 (유일한 오토로드)
│   │   ├── event_bus.gd       # (미등록, 잔재)
│   │   ├── game_state.gd      # (미등록, 잔재)
│   │   ├── game_stats.gd      # (미등록, 잔재)
│   │   └── modifier_db.gd     # (미등록, 잔재)
│   ├── stages/
│   │   ├── stage_01.gd        # 메인 루프
│   │   └── unfold_field.gd    # 필드 로직
│   ├── ui/
│   │   ├── skill_tree.gd
│   │   ├── skill_node.gd
│   │   └── battle_view.gd
│   ├── entities/
│   │   ├── hero.gd
│   │   ├── slime_marker.gd
│   │   ├── gold_pickup.gd
│   │   ├── sword_pickup.gd
│   │   └── floating_pickup.gd
│   ├── runtime/
│   │   └── (다수 — 옛 프로토타입 잔재, 정리 대상)
│   └── data/
│       ├── skill_node_data.gd # ✅ 현재 사용 중
│       ├── enemy_data.gd
│       ├── character_data.gd
│       ├── item_data.gd
│       └── modifier_data.gd
│
├── data/
│   ├── skill_nodes/           # ✅ 노드 .tres들
│   └── enemies/
│       └── slime.tres
│
└── assets/
    ├── sprites/
    └── fonts/
```

**정리 필요:** `scripts/runtime/` 안에 옛 prototype 잔재 다수 (`main.gd`, `home_base.gd`, `manual_battle.gd`, `event_window.gd`, `town2*.gd`, `player.gd`, `minimal_main.gd` 등). `scenes/` 루트의 옛 씬들도 마찬가지.
**원칙:** 현재 진입점(`stage_01`)에서 도달하지 않는 파일은 *유지하지 말고 지운다.* 다만 한 번에 하지 말고 사용자와 합의 후 단계적으로.

---

## 🎨 비주얼 시스템

```
해상도: 640 × 360 (절대 변경 X)
픽셀 아트: 16x16 기반
폰트: M6X11 / DungGeunMo (한국어)
톤: 드퀘 1986 (검정 배경 + 흰 테두리 + 흰 텍스트)

전투창:
- 흰 테두리 + 검정 배경
- 적 정면 그림 + 명령 메뉴

필드:
- 단순 녹색 사각 (현재) → 향후 지역 배경
- 적/픽업/장비 모두 16x16 픽셀
```

---

## 🚨 절대 안 할 것 (제작 중)

```
❌ 코드로 UI 노드 생성 (씬에서 배치)
❌ 직접 노드 참조 (시그널 사용)
❌ 오토로드 남용 (RunState로 충분한지 먼저 확인)
❌ 상수 박제 (@export 사용)
❌ 매직 넘버 (인스펙터에서 조정)

❌ 비전 흔들기 — *언폴드 = 핵심 메타포*
❌ "Pure UI 인크리멘탈"로 회귀하기 (작은 세계가 캔버스인 게 후크)
❌ 페일 스테이트 추가 (인크리멘탈 정의에 어긋남)
❌ 완벽 추구 (작동 추구)
❌ 새 시스템 즉흥 추가 (아이디어는 NEW_IDEAS.md 같은 격리 박스로)
```

---

## 🎯 클코 작업 프로토콜

### **클코 역할**

```
✅ 코드 작성 / 리팩터
✅ Godot 4 모범 패턴 적용 (위 7개 원칙 준수)
✅ 명확한 일 단위 처리
✅ 잔재 정리 (사용자 합의 후)

❌ 디자인 결정 (장르/메커니즘/밸런싱은 사용자가)
❌ "이렇게 하면 더 좋을까요?" 식 우회 제안 (확인 X, 지시 따르기)
❌ 새 시스템 즉흥 제안
❌ 비전 변경
```

### **사용자(개발자) 역할**

```
✅ 모든 디자인 결정
✅ 비전 유지
✅ 새 노드 / 메커니즘 정의
✅ 밸런싱 (cost, timer, 데미지 등)
✅ 에셋 (도트, 폰트)
✅ 플레이 테스트

❌ 갈아엎기 모드
```

---

## 🌟 핵심 격언

```
1. "세계가 한 칸씩 펼쳐진다."
2. "숫자보다 *사물*이 등장한다."
3. "페일 스테이트 없다 — 진행이 멈출 뿐."
4. "Boring is better than confusing."
5. "좋은 시스템은 안 보인다."
6. "결과가 아니라 행위다."
```

---

## 🚨 함정 안내문

```
함정 1: 시스템 추가 욕구 → 노드 1개로 표현 가능한지 먼저 검토
함정 2: 다른 인크리멘탈 따라하기 → 우리 후크(시각적 세계)는 보호
함정 3: AI한테 비전 위임 → 언폴드 메타포 박혀 있는지 확인
함정 4: "Pure UI가 진짜 인크리멘탈이지" → NO. 우리는 변주다.
함정 5: 완벽 추구 → 작동 추구
함정 6: 새 아이디어 즉시 반영 → 격리 박스로
함정 7: 페일 스테이트 (죽음/게임오버) 도입 → 장르 어긋남
함정 8: 런 시간 늘리기 (10초 → 30초) → 해금이 늘려주는 거지 기본을 늘리지 마
```

---

## 💪 작업 리듬

```
- 매일 작은 완성 + 트위터 공개
- 25분 작업 + 5분 휴식 (포모도로)
- 흥분 모드 진입 시 격리 박스
- 갈아엎기 모드 = STOP, 현재 빌드 공개
```

가자! 🍺🎮✨

*"엉덩이 붙이고 만든다."*
*This is the way.*
