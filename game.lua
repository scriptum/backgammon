local ffi = require 'ffi'

ffi.cdef[[
typedef struct DNA {
	double fill;            //вес за каждую забитую клетку
	double pair;            //за цепочки
	double pair_end;        //за цепочки в конце
	double chainDist;       //за близость цепочки к фишкам противника
	double holes;           //за дырки
	double pass;            //за то что миновал цепочку (умножает на число перепрыгнутых)
	double onenemybase;     //бонус за каждую фишку на базе противника
	double onenemybase_e;   //бонус за каждую фишку на базе противника в конце
	double movInHome;       //за то, что двигает фишки в доме в конце игры. Нужен тонкий баланс
	double danger_start;    //за забивание опасных клеток в начале игры
	double danger_end;      //за забивание опасных клеток в конце игры
	double danger_add;      //за забивание опасных клеток больше 4
	double canPlace;        //бонус за возможность сходить какую-то цифру, довольно важен
	double opCanPlace;      //то же самое для оппонента
	double nearHome;        //близость к дому
	double head_mul;        //очки за снятие с головы, множитель
	double head;            //очки за снятие с головы, добавочный
	double tower;           //снимаем очки за постройку "башен"
	double length;          //бонус за рассредоточенность (расстояние от самой дальней до самой ближней)
	double length_end;      //бонус за рассредоточенность в конце игры
	double throw;           //вес выкинутой фишки
	double home;            //бонус за каждую фишку в доме
	double home_middle;     //бонус за каждую фишку в доме в середине
	double home_end;        //бонус за каждую фишку в доме в конце
	double field_start[25]; //вес для занимаемых клеток в начале игры
	double field_middle[25];//вес для занимаемых клеток в середине игры
} DNA;
]]

function table2DNA(t)
	local DNA = ffi.new('DNA')
	for k, v in pairs(t) do
		if type(v) == 'table' then
			for i = 1, 24 do
				DNA[k][i] = v[i]
			end
		else
			DNA[k] = v
		end
	end
	return DNA
end

if E then --если с графикой
	--доска
	board = E:new(screen)
	--задаем метрики доски в пикселях относительно масштаба 1024 х 768
	board.chip_size = 45 --размер фишки
	board.chip_space = 6 --свободное пространство между фишками внутри блоков
	board.offsets = {
		874, 15, --позиция правого верхнего блока
		497, 15, --позиция левого верхнего блока
		242, 708, --позиция левого нижнего блока
		619, 708, --позиция правого нижнего блока
		949, 708, --сброс белых
		167, 15 --сброс черных
	}
	--кубики
	dice = E:new(board)
else
	board = {}
	dice = {}
end

--массив доски
board.a = {}
--всего 6*4 клеток + 2 клетки на сброс
for i = 1, 26 do
	table.insert(board.a, {
		chips = 0,
		player = 0, --1 или 2 игрок, 0 - свободна
		top = {} --стек фишек
	})
end

dice.d1 = 1
dice.d2 = 1

function moveChip(chip, pos, check)
	if not chip then 
		print('moveChip error: chip is nil')
		return false 
	end
	if pos == chip.pos then return false end
	local ba = board.a
	if _AI.canPlace(chip, pos) then
		if chip.pos > 0 then
			local bc = ba[chip.pos]
			if table.last(bc.top) ~= chip then return false end
			bc.chips = bc.chips - 1
			if bc.chips == 0 then bc.player = 0 end
			table.remove(bc.top, #bc.top)
		end
		local x, y
		if not check then x, y = getChipXY(pos) end
		ba[pos].chips = ba[pos].chips + 1
		ba[pos].player = chip.player
		table.insert(ba[pos].top, chip)
		if not check then 
			chip:stop('move'):animate({x = x, y = y}, chipAnimTable)
			:stop('shadow'):animate({shadow = 5}, 'shadow')
		end
		chip.pos = pos
		return true
	else
		return false
	end
end

--меняет местами игроков
function swapPlayer(pl)
	return pl == 1 and 2 or 1
end