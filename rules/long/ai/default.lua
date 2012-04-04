return {
	fill = 0.6,          --вес за каждую забитую клетку
	pair = 0.2,          --за цепочки
	pair_end = 0.05,     --за цепочки в конце
	chainDist = 0.2,     --за близость цепочки к фишкам противника
	holes = -0.015,      --за дырки
	pass = 0.2,          --за то что миновал цепочку (умножает на число перепрыгнутых)
	onenemybase = 0.5,   --бонус за каждую фишку на базе противника
	onenemybase_e = 0.2, --бонус за каждую фишку на базе противника в конце
	movInHome = -1.0,    --за то, что двигает фишки в доме в конце игры. Нужен тонкий баланс
	danger_start = 0.04, --за забивание опасных клеток в начале игры
	danger_end = 0.15,   --за забивание опасных клеток в конце игры
	danger_add = 0.4,    --за забивание опасных клеток больше 4
	canPlace = 2,        --бонус за возможность сходить какую-то цифру, довольно важен
	opCanPlace = -3,     --то же самое для оппонента
	nearHome = 0.0015,  --близость к дому
	head_mul = 0.015,    --очки за снятие с головы, множитель
	head = 1,            --очки за снятие с головы, добавочный
	tower = -0.2,        --снимаем очки за постройку "башен"
	length = -0.1,       --бонус за рассредоточенность (расстояние от самой дальней до самой ближней)
	length_end = -0.25,   --бонус за рассредоточенность в конце игры
	throw = 1000,        --вес выкинутой фишки
	home = 0.2,          --бонус за каждую фишку в доме
	home_middle = 0.3,   --бонус за каждую фишку в доме в середине
	home_end = 0.3,      --бонус за каждую фишку в доме в конце
	field_start = {      --вес для занимаемых клеток в начале игры
		0, --1
		1.0, --2
		1.05, --3
		1.1, --4
		1.15, --5
		1.2, --6
		1.25, --7
		0, --8
		0, --9
		0.1, --10
		0.2, --11
		0.0, --12
		0.4, --13
		1.0, --14
		1.6, --15
		1.7, --16
		2, --17
		2, --18
		2, --19
		0, --20
		0, --21
		0, --22
		0, --23
		0  --24
	},
	field_middle = {  --вес для занимаемых клеток в середине игры
		-0.2, --1
		-0.2, --2
		-0.1, --3
		-0.1, --4
		-0.1, --5
		-0.1, --6
		0.3, --7
		0.4, --8
		0.5, --9
		0.6, --10
		0.7, --11
		0.8, --12
		0, --13
		0, --14
		0, --15
		0, --16
		0, --17
		0, --18
		0, --19
		0, --20
		0, --21
		0, --22
		0, --23
		0  --24
	}
}