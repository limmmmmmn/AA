# 현재 진행 구조 구현 매핑

- 기본 시설 시작 배치와 골드 소비/기지 외형 상태: `scripts/game.gd`
- 사건 기반 특수 시설과 자동화 동물 복원: `scripts/main.gd`
- 골드 소프트 캡 UI, 무기점·대장간, 최상위 툴팁: `scripts/hud.gd`, `scenes/hud.tscn`
- 필드 조우 프로필과 황금 슬라임 도주: `scripts/monster.gd`, `scripts/main.gd`
- 중앙 전투 스텝·배속·전투 스냅샷: `scripts/systems/battle_director.gd`

부흥 구매, 건물 기능 해금, 강화 하드캡, 빈 터, 잠긴 창고, 붉은 상자는 사용하지 않는다. 구 세이브의 관련 값은 무시한다.
