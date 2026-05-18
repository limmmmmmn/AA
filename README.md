# Appears! Appears! — 제작 README

> **이 문서는 클로드코드(클코)에게 전달하는 *제작 헌법*이다.**
> **모든 코딩 결정은 이 문서를 따른다.**
>
> 작성: 2026년 5월 / 강원도 작업 시작 직전

---

## ⚡ 게임 한 줄

> **JRPG 멀티 전투창 자동전투 로그라이크. 30분 한 판.**

```
플레이어 = 카메라 = 파티 4명
필드 (탑다운) → 적과 충돌 → 1인칭 전투창 펑
전투창 동시 다수 (최대 100개)
자동 턴제 전투
30초~60초 스테이지 → 정산창 → 다음 스테이지
한 런 = 약 25-30분
```

**트레일러 컷 (북극성):** 화면에 전투창 100개 동시 폭발.

---

## 🎯 강원도 3일 목표

**5초 GIF: "멀티 전투창 작동 + 시너지 폭발"**

```
Day 1: 시스템 골격
- 멀티 전투창 시스템 작동 (10~100개 동시)
- 자동 턴제 전투
- 적 1종 (슬라임)
- 모디파이어 데이터 구조

Day 2: 시너지 검증
- 모디파이어 10~15개
- 빌드 방향 검증 (단일 / 카오스 / 복제)
- 정산창 기본

Day 3: 트레일러 컷 + 폴리시
- 데미지 숫자 연출
- 전투창 가생이 이동
- 5초 GIF 찍기
- 트위터 공개
```

**완성품 X. 작동 증명 ✓.**

---

## 🔧 기술 스택

```
엔진: Godot 4.6
해상도: 640 × 360 (절대 흔들지 마)
언어: GDScript
버전 관리: Git (이미 연동됨)
배포: Steam (장기 목표)
```

---

## 🏗️ Godot 4 제작 원칙 (반드시 지킬 것)

### **원칙 1: 씬 + 노드 우선, 코드 마지막**

**모든 게임 요소는 씬(.tscn)이 먼저, 코드(.gd)는 그 위에 얹기.**

```
❌ 나쁨: 코드로 노드 생성
   var sprite = Sprite2D.new()
   sprite.texture = preload("...")
   add_child(sprite)

✅ 좋음: 씬에서 노드 배치
   - Enemy.tscn에 Sprite2D 노드 배치
   - 인스펙터에서 텍스처 설정
   - 코드는 행동만
```

**이유:** 시각적 디자인 + 디자이너 협업 + 빠른 반복.

### **원칙 2: 시그널로 디커플링**

**노드끼리 직접 호출 X. 시그널로 메시지 전달.**

```
❌ 나쁨: 직접 참조
   var ui = get_node("/root/Main/UI/HPBar")
   ui.update_hp(50)
   → UI 위치 바뀌면 깨짐

✅ 좋음: 시그널 emit
   # Player.gd
   signal hp_changed(new_hp: int)
   func take_damage(amount: int):
       hp -= amount
       hp_changed.emit(hp)
   
   # 인스펙터에서 HPBar의 update_hp에 연결
   → UI 위치 자유
   → Player는 UI 모름
```

**시그널 연결 방식:**
- **에디터 연결 (인스펙터)**: 정적 관계, 시각적으로 보임 → *우선 선택*
- **코드 연결 (`.connect()`)**: 동적 관계 (인스턴스 생성 시) → 필요 시만

### **원칙 3: 시그널 버스 (전역 이벤트)**

**여러 시스템이 알아야 할 이벤트는 시그널 버스로.**

```
✅ 시그널 버스 패턴:

# autoload/EventBus.gd
extends Node

# 게임 전역 이벤트
signal enemy_defeated(enemy: Node, gold: int)
signal stage_cleared(stage_num: int)
signal relic_picked(relic: ModifierData)
signal party_hp_changed(new_hp: int)
signal battle_window_opened(window: Node)
signal battle_window_closed(window: Node)

# 사용 예시:
# Enemy.gd
func die():
    EventBus.enemy_defeated.emit(self, gold_reward)
    queue_free()

# UI.gd (다른 곳)
func _ready():
    EventBus.enemy_defeated.connect(_on_enemy_defeated)

func _on_enemy_defeated(enemy: Node, gold: int):
    update_gold_display(gold)
```

**규칙:**
- 시그널 버스 = 게임 전역 이벤트만
- 로컬 통신은 일반 시그널
- 오토로드 *남용 X* (시그널 버스 + GameState 정도만)

### **원칙 4: 오토로드는 *최소한***

```
✅ 필요한 오토로드 (이 정도만):
- EventBus: 시그널 버스
- GameState: 골드, 파티, 진행 상황
- ModifierDB: 모든 모디파이어 데이터
- AudioManager: 효과음/BGM (필요 시)

❌ 피할 것:
- 모든 시스템을 오토로드로 (전역 상태 폭발)
- 데이터 + 로직 섞기 (테스트 어려움)
- 씬에서 처리 가능한 걸 오토로드에 (응집도 ↓)
```

**원칙: 한 씬에서 끝낼 수 있으면 오토로드 X.**

### **원칙 5: Resource 활용 (데이터 = .tres 파일)**

**모디파이어, 적 데이터, 캐릭터 등은 모두 Resource로.**

```
# scripts/data/modifier_data.gd
class_name ModifierData
extends Resource

@export var id: String
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var rarity: Rarity  # enum
@export var category: Category
@export var effect_data: Dictionary  # 효과 변수

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
enum Category { QUANTITY, CONDITIONAL, TRANSFORM, COMPANION }
```

**이걸 .tres 파일로 만들면 — 인스펙터에서 시각적 편집 가능.**

```
data/modifiers/
  common/
    sword_plus_5.tres
    hp_plus_10.tres
  conditional/
    single_target_boost.tres
    chaos_gold_boost.tres
  transform/
    window_duplicate.tres
  legendary/
    time_freeze.tres
```

**이득:**
- 코드 1줄 = 데이터 100개 추가
- 디자인 변경 = 코드 X, .tres 파일만
- 클코한테 "모디파이어 추가" 시 *코드 X, .tres 생성*만

### **원칙 6: 인스펙터 활용 (@export)**

**모든 변수는 가능한 한 @export로 노출.**

```
✅ 좋음:
@export var move_speed: float = 100.0
@export var max_hp: int = 100
@export var enemy_data: EnemyData
@export var sprite_texture: Texture2D
@export_range(0, 100) var spawn_chance: int = 50

→ 인스펙터에서 조정
→ 코드 수정 X
→ 빠른 밸런싱
```

```
❌ 나쁨:
const MOVE_SPEED = 100.0  # 상수 박제
var max_hp = 100  # 인스펙터 안 보임
```

### **원칙 7: 노드 그룹 활용**

**같은 종류 노드 처리는 그룹으로.**

```
# 적 노드를 "enemies" 그룹에 추가 (씬에서 또는 코드)

# 모든 적 동시 처리
for enemy in get_tree().get_nodes_in_group("enemies"):
    enemy.take_damage(10)

# 또는 시그널 emit
get_tree().call_group("enemies", "take_damage", 10)
```

**이득:** 직접 참조 X, 디커플링 ↑.

### **원칙 8: @onready로 노드 참조**

```
✅ 좋음:
@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = %HPBar  # 고유 이름

❌ 나쁨:
func _ready():
    var sprite = get_node("Sprite2D")  # 매번 검색
```

**이득:** 한 번 캐싱, 명확함, 자동완성.

### **원칙 9: 시그널 매개변수 명시**

```
✅ 좋음:
signal enemy_defeated(enemy: Node, gold: int, position: Vector2)

❌ 나쁨:
signal enemy_defeated  # 어떤 정보?
```

**이득:** 타입 안전, 자동완성, 문서화.

---

## 📁 프로젝트 구조

```
project_root/
├── project.godot
├── README.md (이 문서)
├── VISION.md (디자인 비전)
│
├── scenes/
│   ├── main.tscn                  # 진입점
│   ├── field.tscn                  # 필드 (탑다운)
│   ├── battle_window.tscn          # 1인칭 전투창
│   ├── settlement.tscn             # 정산창
│   ├── hud.tscn                    # HUD
│   ├── enemies/
│   │   ├── slime.tscn
│   │   ├── bat.tscn
│   │   └── zombie.tscn
│   ├── ui/
│   │   ├── modifier_card.tscn
│   │   ├── party_display.tscn
│   │   └── damage_number.tscn
│   └── effects/
│       ├── pickup_glow.tscn
│       └── combat_log.tscn
│
├── scripts/
│   ├── autoload/
│   │   ├── event_bus.gd            # 시그널 버스
│   │   ├── game_state.gd           # 골드, 파티 상태
│   │   └── modifier_db.gd          # 모디파이어 카탈로그
│   ├── runtime/
│   │   ├── main.gd
│   │   ├── field.gd
│   │   ├── battle_window.gd
│   │   ├── enemy.gd
│   │   └── settlement.gd
│   └── data/
│       ├── modifier_data.gd        # Resource 정의
│       ├── enemy_data.gd
│       └── character_data.gd
│
├── data/
│   ├── modifiers/                  # .tres 파일들
│   │   ├── common/
│   │   ├── uncommon/
│   │   ├── rare/
│   │   └── legendary/
│   ├── enemies/
│   ├── characters/
│   └── companions/
│
├── assets/
│   ├── sprites/
│   │   ├── enemies/
│   │   ├── characters/
│   │   └── ui/
│   ├── fonts/                      # M6X11 + 한국어 픽셀 폰트
│   └── audio/
│
└── docs/
    ├── VISION.md                   # 디자인 비전
    ├── NEW_IDEAS.md                # 격리 박스
    └── DEV_LOG.md                  # 진행 로그
```

---

## 🎮 핵심 시스템 설계

### **시스템 1: 멀티 전투창**

```
구조:
- BattleWindow.tscn (씬)
- 동시 다수 인스턴스 (최대 100개)
- 화면 중앙에 등장 → 0.3초 후 가생이로 미끄러짐

생성 흐름:
1. Field에서 적과 충돌 감지
2. EventBus.enemy_encountered.emit(enemy)
3. BattleManager가 BattleWindow 인스턴스 생성
4. add_child(window)
5. 위치 결정 알고리즘 (가용 자리)
6. 자동 턴제 전투 시작

종료:
1. 적 처치 → EventBus.enemy_defeated.emit
2. 골드 카운트 + 데미지 숫자 popup
3. 0.3초 후 window.queue_free()
```

**핵심: BattleWindow는 *독립적 인스턴스*. 서로 안 알게.**

### **시스템 2: 자동 턴제 전투**

```
턴 속도: 0.5초/턴 (인스펙터 조정 가능)

순서:
1. 파티 4명 동시 행동 (한 번에 4공격)
2. 0.5초 대기
3. 적 그룹 한 번에 행동
4. 0.5초 대기
5. 반복

파티 = 추상 (시스템 3 참고)
- 전투창에 "보이지 않음"
- HUD 하단에 HP만 표시
- 모든 전투창에서 동시 작동
```

### **시스템 3: 파티 = 카메라 (추상)**

```
파티는 위치 없음.
화면 = 파티의 시야.

구현:
- Party는 GameState에 데이터로만 존재
- 필드에 *작은 도트 마커*로 표시 (선택)
- 전투창엔 "보이지 않음"
- HUD 하단에 4명 정보

데미지 처리:
- 어떤 전투창에서 데미지 받든
- GameState.party_hp 깎임
- EventBus.party_hp_changed.emit
- HUD 자동 업데이트
```

### **시스템 4: 모디파이어 (렐릭)**

```
구조: Resource (.tres)
저장: data/modifiers/ 폴더
관리: ModifierDB 오토로드

ModifierData 필드:
- id, name, description, icon
- rarity (Common/Uncommon/Rare/Legendary)
- category (Quantity/Conditional/Transform/Companion)
- effect_data (Dictionary)

사용:
- GameState.active_modifiers: Array[ModifierData]
- 적 처치/데미지 계산 시 모든 모디파이어 순회
- 효과 적용

추가:
- 새 .tres 파일만 만들면 끝
- 코드 수정 X
```

### **시스템 5: 정산창**

```
씬: settlement.tscn
구조:
- 4슬롯 모디파이어 카드 (UI)
- 골드 표시
- "리프레시" 버튼 (옵션)
- "다음 지역" 버튼 (명확한 출구)

흐름:
1. 스테이지 끝 → settlement.tscn 인스턴스
2. ModifierDB.get_random_modifiers(4) 받음
3. 4슬롯에 표시
4. 플레이어 구매 시 EventBus.modifier_purchased.emit
5. "다음 지역" 클릭 → settlement.queue_free()
6. 다음 스테이지 시작

UI 원칙:
- 그림 위주 (텍스트 최소)
- 4슬롯 고정
- 희귀도 색깔
- 명확한 출구
- 확인 다이얼로그 X
```

### **시스템 6: HUD**

```
씬: hud.tscn (CanvasLayer)
위치: 화면 하단

표시:
- 파티 4명: 이름, HP, MP, 레벨
- 골드 (현재)
- 스테이지 진행 (시간 또는 카운트)

업데이트:
- EventBus 시그널 수신
- party_hp_changed → HP 바 갱신
- gold_changed → 골드 표시
- 자동 (직접 호출 X)
```

---

## 🎨 비주얼 시스템

```
해상도: 640 × 360 (절대 변경 X)
픽셀 아트: 16x16 기반 (적, 캐릭터)
폰트: M6X11 (영문/숫자) + DungGeunMo (한국어)
색깔: 드퀘 1986 톤

전투창:
- 흰 배경 + 검정 테두리
- 적 정면 그림 (32x32~64x64)
- 적 이름 (텍스트)
- HP 바
- 데미지 로그 (1줄)

지역 배경 (전투창 내부):
- 6개 지역 × 1배경 = 6장
- 단순 픽셀
- 같은 지역 = 같은 배경 (성능 + 통일감)

캐릭터:
- 좌/우 도트만 (앞/뒤 X)
- 초상화 1장
```

---

## 🚨 절대 안 할 것 (제작 중)

```
❌ 코드로 UI 노드 생성 (씬에서 배치)
❌ 직접 노드 참조 (시그널 사용)
❌ 오토로드 남용 (필요한 것만)
❌ 상수 박제 (@export 사용)
❌ 데이터 코드에 박제 (Resource 사용)
❌ 매직 넘버 (인스펙터에서 조정)

❌ 새 시스템 추가 (시스템 13개로 완성)
❌ 기존 결정 흔들기
❌ "더 좋은 방법" 시도 (검증 후만)
❌ 완벽 추구 (작동 추구)
```

---

## 🎯 클코 작업 프로토콜

### **세션 시작 정형:**

```
[VISION.md 첨부]
[README.md 첨부]

오늘 작업: [구체적 일 단위]
확정된 결정: [목록]
하지 말 것: [함정 목록]

질문 시: 비전/제작 원칙 따라 답하기
임의 결정 X. 명시적 지시만.
```

### **클코 역할:**

```
✅ 코드 작성
✅ Godot 4 모범 패턴 적용
✅ 위 9개 원칙 준수
✅ 명확한 일 단위 처리

❌ 디자인 결정
❌ "이렇게 하면 더 좋을까요?" (확인 X, 지시 따르기)
❌ 새 시스템 제안
❌ 비전 변경
```

### **나(개발자) 역할:**

```
✅ 디자인 결정 (모든 결정)
✅ 비전 유지
✅ 함정 자가 감지
✅ 플레이 테스트
✅ 밸런싱
✅ 모디파이어 텍스트
✅ 에셋 (도트, 초상화)
✅ 하루 끝 진행 공개 (트위터)

❌ 클코 결정 의존
❌ 비전 흔들기
❌ 갈아엎기 모드
```

---

## 📋 Day 1 To-do (도착 즉시)

```
1. [ ] Godot 프로젝트 백업 (현재 헥스 타일 버전)
2. [ ] 새 브랜치: "multi-window-prototype"
3. [ ] 클코에 VISION.md + README.md 첨부
4. [ ] 첫 프롬프트:
       "프로젝트 구조 만들어줘:
        - autoload/ event_bus.gd, game_state.gd, modifier_db.gd
        - scenes/ main.tscn, field.tscn, battle_window.tscn
        - scripts/data/ modifier_data.gd (Resource)
        Godot 4.6 모범 패턴 (시그널 + Resource + @export)"
5. [ ] BattleWindow 씬 만들기 (단일)
6. [ ] 슬라임 적 1종 (Resource + 씬)
7. [ ] 모디파이어 5개 (.tres 파일)
8. [ ] 단일 전투창 작동 확인
9. [ ] 트위터: "Day 1 시작" 진행 보고
```

---

## 📋 Day 2 To-do

```
1. [ ] 멀티 전투창 (10개 동시)
2. [ ] 가생이 이동 알고리즘
3. [ ] 모디파이어 10~15개 추가
4. [ ] 시너지 검증 (단일/카오스 빌드)
5. [ ] 정산창 기본
6. [ ] 트위터: "Day 2 시너지 폭발"
```

---

## 📋 Day 3 To-do

```
1. [ ] 100개 전투창 시도
2. [ ] 데미지 숫자 연출
3. [ ] Legendary 모디파이어 1~2개
4. [ ] 5초 GIF 찍기
5. [ ] 트위터 공개 (추악해도)
```

---

## 🌟 핵심 격언 (코딩 중 흔들리면 봐)

```
1. "전투는 플레이어가, 모험은 필드 캐릭터가."
2. "결과가 아니라 행위다."
3. "디자인은 시스템이 아니라 디테일이다."
4. "Boring is better than confusing."
5. "신선함 < 단순함의 재미."
6. "좋은 시스템은 안 보인다."
7. "UI는 게임의 일부."
8. "미묘한 차이가 명작을 만든다."
```

---

## 🚨 함정 안내문 (반복)

```
함정 1: 시스템 추가 욕구 → 디테일 조정
함정 2: 다른 게임 따라하기 → 우리 후크 보호
함정 3: AI한테 비전 위임 → 트레일러 컷 봐
함정 4: 완벽 추구 → 작동 추구
함정 5: 갈아엎기 → 디테일 검토
함정 6: 새 아이디어 → 격리 박스 (NEW_IDEAS.md)
함정 7: "재미 추가될까?" → 24시간 자기 검증
함정 8: 다른 게임 좋은 메커니즘 → 우리 톤 검증
함정 9: 발걸음 시스템 → 추가 X
함정 10: 합체 공격 → 동료 캐릭터로 변주
함정 11: 쿨다운 → 턴제 유지
함정 12: 인게임 정비 → 정산창에만
함정 13: 자동 이동 → 수동 이동 유지
```

---

## 💪 너 자신에게

```
✨ 너 강점:
- 6개월 R&D + 6시간 디자인 토론 = 명확한 비전
- 텀블벅 2회 1등 = 데드라인 패턴 검증
- 메타인지 = 함정 자가 감지
- 솔직함 + 외부 검증 자세

✨ 작업 리듬:
- 매일 작은 완성 + 트위터 공개
- 25분 작업 + 5분 휴식 (포모도로)
- 흥분 모드 진입 시 격리 박스
- 갈아엎기 모드 = STOP, 현재 빌드 공개

✨ 100만장 가는 길:
강원도 5초 GIF → 트레일러 → 위시리스트 → 데모 → EA → 1.0
약 9~12개월
Megabonk이 했음. 너도 가능.

가자!! 🍺🎮✨
```

---

*"엉덩이 붙이고 만든다." - 너 한 말, 박아둠.*
*This is the way.*
