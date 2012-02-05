require 'lib.cheetah'
require 'lib.lquery.init'
local C = cheetah
C.init('Long backgammon game', 1024, 768, 32, 'v')
C.print = C.fontPrint

require 'data.tahoma'
require 'lib.table'

lQuery.addhook(function()
	C.reset() -- сброс координат
	C.scale(1, 1) --масштаб
end)

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
E:new(board):image('data/bg1.png')
local shadows = E:new(board) --тени
E:new(board):image('data/bg.png')

local shadow = C.newImage('data/shadow.png')
local shadowOff = 9
for i = 1, 30 do
	E:new(shadows):draw(function(s)
		local c = chips._child[i]
		--if c.shadow == 0.01 then c.shadow = 0 end
		if c.shadow < 3 then
			local x, y = c.x - shadowOff,c.y - shadowOff
			C.translateObject(x, y, math.atan((-64-x)/(y))/math.pi*180+45, 64, 64, 32, 32)
			C.Color(255,255,255,255 - c.shadow*255/3)
			shadow:draw()
		end
	end)
end

--кубики
dice = E:new(board)
dice.sprite = {}
for i = 1, 6 do
	table.insert(dice.sprite, C.newImage('data/dice/dice_' .. i ..'.png'))
end
dice:draw(function(s)
	s.sprite[s.d1]:draw()
	C.move(1.064,0)
	s.sprite[s.d2]:draw()
end):move(10, 20):size(70,70)

--массив игровых состояний
local game = {
	player = 0, --кто ходит 1 или 2
	first_move = {true, true}, --первый/второй игрок ходит первый раз
	allow_two_from_head = false,
	throw = {false, false}, --первый/второй игрок может скидывать
	inhome = {0,0}, --сколько в доме
	row = {false, false}, --первый/второй игрок может выстроить ряд из шести
	moves = {}, --просто список ходов
	last = {1,1}
}
local game_old

local chip = {checkers = C.newImage('data/checkers.png'), black = C.newImage('data/black.png'), white = C.newImage('data/white.png'), highlight = C.newImage('data/green.png'), select = C.newImage('data/select.png'), tip = C.newImage('data/tip.png'), tip2 = C.newImage('data/tip2.png'), spec = C.newImage('data/check_spec.png')}
local button = C.newImage('data/button.png')

--~ local allMoves = E:new(board)
--~ allMoves.a = {} --массив содержит все ходы, которые нужно сделать игроку

local function loop(num) --зацикливает доску
	return (num - 1) % 24 + 1
end

local function inr(v, a, b) --проверяет, лежит ли v между  a и b
	return v >= a and v <= b
end

--функция, вычисляющая координаты фишки в зависимости от позиции и наличия на клетке фишек
local function getChipXY(pos)
	local b = board
	local x, y
	if pos == 25 then 
		x, y = b.offsets[9], b.offsets[10] - b.chip_size * b.a[pos].chips
	elseif pos == 26 then 
		x, y = b.offsets[11], b.offsets[12] + b.chip_size * b.a[pos].chips
	else
		local p = math.floor((pos - 1) / 6) * 2 + 1
		x = b.offsets[p] + ((pos - 1) % 6) * (pos > 12 and 1 or -1) * (b.chip_size + b.chip_space)
		y = b.offsets[p+1] + b.chip_size * b.a[pos].chips * (pos > 12 and -1 or 1)
	end
	return x, y
end

local moveDepth --глубина хода
local maxChain --максимально возможная глубина хода
--генерирует и подсвечивает возможные ходы, когда игрок берет фишку
local allowedMoves = E:new(board)
allowedMoves._child = {}
local function addAllowedMove(pos, v, lvl)
	if maxChain > #allowedMoves._child then
		E:new(allowedMoves):image(chip.highlight):move(getChipXY(pos)):set({a = 127, pos = pos, count = v[2], pointer = v[1], lvl = lvl})
	end
end

local function canPlace(ch, pos) --проверяет, можно ли класть сюда фишку
	local p = board.a[pos].player
	return (p == 0 or p == ch.player)
end

local moves
local movesTree
local movPointer --указатель на участок дерева, с которого начинать движение
local function genMoves(ch, pos, ptr, lvl) --генерирует возможные ходы TODO: отсечение неполных ходов
	if not ptr then ptr = movPointer end
	if not lvl then lvl = 1 end
	if not pos then pos = ch.pos end
	local a = ptr[pos]
	if not a then return end
	local newpos
	for k,v in ipairs(a) do
		newpos = v[3]
		addAllowedMove(v[3], v, lvl)
		if v[1][newpos] then
			genMoves(ch, newpos, v[1], lvl + 1)
		end
	end
end

local function isChipInTop(chip)
	return chip.pos ~= 0 and table.last(board.a[chip.pos].top) == chip and chip.player == game.player
end

--функция перемещения фишки
local chipAnimTable = {speed = 0.7, queue = 'move', callback = function(s)
	s:animate({shadow = 0}, {'shadow', speed = 0.7})
end}
chips = E:new(board)
local function moveChip(chip, pos, check)
	if pos == chip.pos then return false end
	local b = board
	if canPlace(chip, pos) then
		if chip.pos > 0 then
			local bc = b.a[chip.pos]
			if table.last(bc.top) ~= chip then return false end
			bc.chips = bc.chips - 1
			if bc.chips == 0 then bc.player = 0 end
			table.remove(bc.top, #bc.top)
		end
		local x, y
		if not check then x, y = getChipXY(pos) end
		b.a[pos].chips = b.a[pos].chips + 1
		b.a[pos].player = chip.player
		table.insert(b.a[pos].top, chip)
		if chip.player == 1 then
			if inr(pos, 19, 25) and not inr(chip.pos, 19, 25) then game.inhome[1] = game.inhome[1] + 1 end
			if inr(chip.pos, 19, 25) and not inr(pos, 19, 25) then game.inhome[1] = game.inhome[1] - 1 end
		else
			if (inr(pos, 7, 12) or pos == 26) and not (inr(chip.pos, 7, 12) or chip.pos == 26) then game.inhome[2] = game.inhome[2] + 1 end
			if (inr(chip.pos, 7, 12) or chip.pos == 26) and not (inr(pos, 7, 12) or pos == 26) then game.inhome[2] = game.inhome[2] - 1 end
		end
		if not check then 
			chip:stop('move'):animate({x = x, y = y}, chipAnimTable)
			:animate({shadow = 5}, 'shadow')
			if chip.pos > 0 then chip.head = false end
		end
		chip.pos = pos
		return true
	else
		return false
	end
end
E.button = function(e, text)
	e._text = text
	e._opacity = 0
	e._active = 0
	e:draw(function(s)
		C.Color(150+s._active,150+s._active,150+s._active,255)
		button:draw()
		C.setBlendMode('additive')
		C.Color(255,255,255, (s._opacity + (lQuery.MousePressedOwner == s and 70 or 0)) * s._active / 105)
			button:draw()
		C.pop() C.push() --рестарт матрицы
		C.move(s.x + (lQuery.MousePressedOwner == s and 1 or 0), s.y+8 + (lQuery.MousePressedOwner == s and 1 or 0))
		C.setBlendMode('alpha')
		C.Color(150+s._active,150+s._active,150+s._active,255)
		Fonts["Tahoma"][10]:printf(s._text, 152, 0)
	end):mouseover(function(s)
		s:stop('fade'):animate({_opacity = 70}, 'fade') 
	end):mouseout(function(s)
		s:stop('fade'):animate({_opacity = 0}, {speed = 1, queue = 'fade'})
	end):size(button.w, button.h)
	e.deactivate = function(s)
		s:stop('active'):animate({_active = 0}, 'active')
	end
	e.activate = function(s)
		s:stop('active'):animate({_active = 105}, 'active')
	end
	return e
end

local function sixInRowCount(pos, player)
	local count = 1
	local b = board.a
	for i = 1, 5 do
		if b[loop(pos+i)].player == player then 
			count = count + 1 
		else break
		end
	end
	for i = 1, 5 do
		if b[loop(pos-i)].player == player then 
			count = count + 1 
		else break
		end
	end
	return count
end

local function sixInRow(pos) --проверка на забивание 6 подряд
	local count = 1
	if game.player == 1 then --для первого игрока
		if pos < 13 and (game.last[2] - 12) < pos then --верхняя половина
			count = sixInRowCount(pos, 1)
		elseif pos > 12 and (game.last[2] + 12) < pos then --нижняя
			count = sixInRowCount(pos, 1)
		end
	else --для второго игрока
		if game.last[1] < pos then
			count = sixInRowCount(pos, 2)
		end
	end
	if count > 5 then return false end
	return true
end

local throwMove = nil
local function canThrow(pos, player, move)
	local t = true --эта фишка последняя?
	for i = 1, 5 do
		if board.a[pos-i].chips > 0 then
			t = false
			break
		end
	end
	throwMove = pos + (player - 1) * 12 + move + player - 1
	if t and throwMove > 24 + player then throwMove = 24 + player end
	if throwMove == 24 + player then
	print(pos, player, move)
	return true end
	throwMove = nil
	return false
end
--построение дерева возможных ходов
local double
local function generateMoves(lvl, head, taken_from_head, ar)
	local b = board.a
	local bb, ch, from_head, isInHome
	if lvl > maxChain then maxChain = lvl end
	if lvl > 4 then return end
	for k, currMove in ipairs(moves) do
		if currMove > 0 then
		for i = 1, 24 do
			bb = b[i]
			if bb.chips > 0 then --если здесь есть фишки
				ch = table.last(bb.top)
				cp = ch.player
				isInHome = (game.inhome[cp] == 15)
				throwMove = nil
				from_head = (cp == 1 and i == 1 or cp == 2 and i == 13)
				if cp == game.player --проверяем ходы только текущего пользователя
				and (((not (head and from_head)) --выкидываем варианты с головы, если с головы уже снимали
				or game.allow_two_from_head and taken_from_head < 2) --за исключением частного случая - дубль в начале игры
				and (cp == 2 and (i < 13 and (i + currMove < 13) or i >12) or cp == 1 and i + currMove <= 24) --не позволять ходить кругами
				or isInHome and canThrow(i, cp, currMove)) --скидывание
				then
				if moveChip(ch, throwMove or loop(i + currMove), true) then --если ход возможен (пока простая проверка, отсекает очевидно невозможные варианты) - как бы делаем его и рекурсивно повторяем процесс
					print(string.rep("    ", lvl-1) .. i .. " - " .. currMove)
				if sixInRow(loop(i + currMove)) then --правило забивания шести
					if not ar[i] then
						ar[i] = {}
					end
					ar[i][#ar[i]+1] = {{}, currMove, throwMove or loop(i + currMove)}
					if not double then moves[k] = 0 end
					generateMoves(lvl + 1, 
						head or ch.head and from_head, 
						from_head and taken_from_head + 1 or taken_from_head, 
						ar[i][#ar[i]][1], 
						currMove)
					if not double then moves[k] = currMove end
				end
					moveChip(ch, i, true)
				end
				end
			end
		end
		end
	end
end


local function boardPrepass()
	local player_1_throw, player_2_throw = true, true
	local b
	for i = 1, 24 do
		b = board.a[i]
		if b.chips > 0 then
			if b.player == 1 then
				if game.last[1] < i then game.last[1] = i end
			end
			if b.player == 2 then
				if game.last[2] < loop(i+12) then game.last[2] = loop(i+12) end
			end
		end
	end
end

local endTurn = E:new(board)
local undo = E:new(board)

local function doRoll()
	game.player = game.player == 1 and 2 or 1
	undo:deactivate()
	undo.u = {}
	endTurn:deactivate()
	movesTree = {}
	if dice.d1 == dice.d2 then
		moves = {dice.d1}
		double = true
		--первый ход, дубль, снимаем две с головы
		if game.first_move[game.player] and (dice.d1 == 3 or dice.d1 == 4 or dice.d1 == 6) then
			game.allow_two_from_head = true
		end
	else
		moves = {dice.d1,dice.d2}
		double = false
	end
	movesTree = {}
	maxChain = 0
	moveDepth = 1
	boardPrepass() --предпроход доски - нужно для выполнения некоторых проверок
	generateMoves(1, false, 0, movesTree, 0)
	movPointer = movesTree
	game.first_move[game.player] = false
	game.allow_two_from_head = false
	if maxChain == 1 then endTurn:activate() end
end

dice.roll = function() --бросок кубиков
	if endTurn._active == 105 then 
		game_old = table.copy(game)
		math.randomseed(os.time() + C.getMouseX() + math.random(99999))
		dice.d1 = math.random(1, 6)
		math.randomseed(os.time() + C.getMouseY() + math.random(99999))
		dice.d2 = math.random(1, 6)
		doRoll()
	end
end

E:new(board):button('Load'):move(7, 600):click(function() --загрузка
	local s = require 'save.game'
	local p = {1, 1}
	local c, x, y
	for pos, v in ipairs(s[1]) do
		board.a[pos] = {
			chips = 0,
			player = v.player,
			top = {}
		}
		for i = 1, v.chips do
			while chips._child[p[v.player]].player ~= v.player do p[v.player] = p[v.player] + 1 end
			c = chips._child[p[v.player]]
			c.pos = pos
			if i == 1 and v.player == 1 then c.head = true end
			if i == 2 and v.player == 2 then c.head = true end
			x, y = getChipXY(pos)
			c:stop('move'):animate({x = x, y = y}, chipAnimTable)
			board.a[pos].chips = i
			table.insert(board.a[pos].top, c)
			p[v.player] = p[v.player] + 1
		end
	end
	game = table.copy(s[2])
	game_old = table.copy(game)
	dice.d1, dice.d2 = s[3], s[4]
	allowedMoves._child = {}
	doRoll()
end):activate()
E:new(board):button('Save'):move(7, 640):click(function() --сохранение
	local s = 'return{{'
	for _, v in ipairs(board.a) do
		s = s .. table.serialize(v, true) .. ','
	end
	C.putFile('save/game.lua', s..'},'.. --поле
	table.serialize(game_old)..--игра
	','..dice.d1..','..dice.d2..'}') --кубики (3,4)
end):activate()

endTurn:button('End turn'):move(7, 680):click(dice.roll)
endTurn._active = 105
undo:button('Undo'):move(7, 720)
:click(function(s)
	if #s.u > 0 then
		local u = table.last(s.u)
		moveChip(u[1], u[2])
		movPointer = u[3] --восстанавливаем позицию в дереве
		moveDepth = u[4]
		table.remove(s.u, #s.u)
		if #s.u == 0 then
			s:deactivate()
		end
		endTurn:deactivate()
	end
end)
undo.u = {}

local chiptip = E:new(board):color(255,255,255,0):draw(function(s)
	if s.a > 0 and s.bestv then
		if s.y > 380 then
			chip.tip:draw()
		else
			C.move(0, 1 + 45/64)
			chip.tip2:draw()
			C.move(0, 0.5)
		end
		C.scale(0.25*0.9, 0.5*0.9)
		C.move(0.05, 0.05)
		local c = s.bestv.lvl
		C.move((4 - c)/2*1.1+0.025*c/2, 0)
		if dice.d1 == dice.d2 then
			for i = 1, c do
				dice.sprite[dice.d1]:draw()
				C.move(1.1, 0)
			end
		elseif c == 2 then
			dice.sprite[dice.d1]:draw()
			C.move(1.1, 0)
			dice.sprite[dice.d2]:draw()
		else
			dice.sprite[s.bestv.count]:draw()
		end
	end
end):size(128, 64)

local function getBestDist(x, y) --лучшее расстояние до возможного хода на доске
	local bestpos, dist, bestv
	local bestdist = 999999
	--если есть возможные ходы
	if #allowedMoves._child > 0 then
		for k, v in ipairs(allowedMoves._child) do
			dist = (v.x - x)*(v.x - x) + (v.y - y)*(v.y - y)*0.05
			if dist < 15000 then
				if dist < bestdist then
					bestdist = dist
					bestpos = v.pos
					bestv = v
				end
			end
		end
	end
	return bestpos, bestv
end

local function allowedChildFadeout()
	for _, v in ipairs(allowedMoves._child) do
		if v._hover == true then 
			v._hover = false 
			v:stop():animate({a = 127}) 
			chiptip:stop():animate({a = 0})
		end
	end
end

local function initChips(color, offsetx, offsety)
	for i = 0, 14 do
		local ch = E:new(chips):move(offsetx, offsety):size(board.chip_size,board.chip_size)
		--перегрузка стандартного Drag'n'Drop движка
		:mousepress(function(c, x, y)
			if isChipInTop(c) then
				--поднимаем фишку вверх над остальными
				for k, v in ipairs(chips._child) do
					if v == c then table.remove(chips._child, k) break end
				end
				table.insert(chips._child, c)
				c:stop('move')
				c:stop('shadow'):animate({shadow = 7}, 'shadow')
				lQuery.drag_start(c, x, y)
			end
			c._ox = c.x
			c._oy = c.y
		end)
		:mouserelease(function(c) --TODO: какой-тобаг с перемещением назад
			if isChipInTop(c) then
				lQuery.drag_end(c)
				if c._ox ~= c.x or c._oy ~= c.y then
					local bestpos, bestv = getBestDist(c.x, c.y)
					if bestpos then
						undo:activate()
						table.insert(undo.u, {c, c.pos, movPointer, moveDepth})
						moveChip(c, bestpos)
						movPointer = bestv.pointer
						moveDepth = moveDepth + bestv.lvl
						allowedMoves._child = {}
						if moveDepth == maxChain then endTurn:activate() end
					else
						local b = board.a[c.pos]
						b.chips = b.chips - 1
						local x, y = getChipXY(c.pos)
						c:stop('move'):animate({x = x, y = y}, 'move')
						b.chips = b.chips + 1
					end
					if #allowedMoves._child == 0 then genMoves(c) end
				else
					allowedChildFadeout()
				end
				chiptip:stop():animate({a = 0})
				c:stop('shadow'):animate({shadow = 0.01}, {queue = 'shadow', speed = 1})
			end
		end)
		:set({img = color, highlight = 0, player = (color == chip.white and 1 or 2), 
		pos = 0, shadow = 0, head = true, _drag_callback = function(s)
			local bestdist, bestv = getBestDist(s.x, s.y)
			if bestv then
				if not bestv._hover then
					bestv._hover = true
					bestv:stop():animate({a = 255})
					chiptip.bestv = bestv
					local x, y = bestv.x + 22 - 64, bestv.y - 64
					if chiptip.a == 0 then chiptip:move(x,y) end
					chiptip:stop():animate({a = 255, x = x,y = y})
					for _, v in ipairs(allowedMoves._child) do
						if v ~= bestv and v._hover == true then v._hover = false v:stop():animate({a = 127}) end
					end
				end
			else
				allowedChildFadeout()
			end
		end})
		:draw(function(s)
			local cs = board.chip_size
			if s.shadow > 0 then
				C.reset()
				local x, y = s.x - shadowOff + s.shadow, s.y - shadowOff + s.shadow
				C.translateObject(x, y, math.atan((-64-x)/(y))/math.pi*180+45, 64, 64, 32, 32)
				C.Color(255,255,255,math.min(s.shadow*255/3,255))
				shadow:draw()
				C.reset()
				C.translateObject(s.x, s.y, s.angle, s.w, s.h, s.ox, s.oy)
			end
			C.Color(255,255,255,255)
			chip.checkers:drawq(s.qx, s.qy, 64, 64)
			C.reset()
			C.translateObject(s.x, s.y, math.atan((-64-s.x)/(s.y))/math.pi*180+45, s.w, s.h, s.ox, s.oy)
			C.setBlendMode('detail')
			chip.spec:draw()
			C.setBlendMode('additive')
			C.Color(255,255,255,s.highlight)
			chip.checkers:drawq(s.qx, s.qy, 64, 64)
			C.setBlendMode('alpha')
		end)
		:mouseover(function(chip)
			if isChipInTop(chip) then
				genMoves(chip)
				chip:stop('hover'):animate({highlight = 150}, 'hover')
			end
		end)
		:mouseout(function(chip)
			if isChipInTop(chip) then
				allowedMoves._child = {}
			end
			chip:stop('hover'):animate({highlight = 0}, {queue = 'hover', speed = 1})
		end)
		local buf = i % 8
		ch.qx = buf * 64
		ch.qy = (math.floor(i/8) + (ch.player - 1) * 2) * 64
		ch.angle = math.random(0,360)
		ch.ox = 32*45/64
		ch.oy = 32*45/64
	end
end

initChips(chip.white, board.offsets[1], board.offsets[2])
initChips(chip.black, board.offsets[5], board.offsets[6])

--сброс фишек к начальным позициям для начала новой игры
local function resetChips()
	local x, y
	for i, v in ipairs(chips._child) do
		if v.player == 1 then
			moveChip(v, 1)
		else
			moveChip(v, 13)
		end
	end
end

resetChips()
dice.roll()
--просто вывод фпс
local smallFont = Fonts["Tahoma"][8]
E:new(screen):draw(function()
	smallFont:print("fps: " .. math.floor(C.FPS) .. ", mem: " .. gcinfo(), 100, 0)
end):move(0,768-12)

C.mainLoop()
