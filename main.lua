require 'lib.cheetah'
require 'lib.lquery.init'
local C = cheetah
C.init('Long backgammon game', 1024, 768, 32, 'vr')

math.randomseed(os.time())

local fast = true
--~ local compVsComp = true

--~ local tests = true
--~ local makeAns = true

--~ if not tests then
	C.init('Long backgammon game', 1024, 768, 32, 'vr')
--~ end


local delayBetweenMoves = 1.99
local delayMove = 0.9
local delayComputerMove = 1.2
local editmode = false
if fast then
	delayBetweenMoves = 0.3
	delayMove = 0.3
	delayComputerMove = 0.4
elseif veryfast then
	delayBetweenMoves = 0.001
	delayMove = 0
	delayComputerMove = 0
end

require 'data.tahoma'
require 'lib.table'

--~ 
--~ getScale = function(w, h)
  --~ local aspect = w/h
  --~ local s = 1
  --~ local x = 0
  --~ local y = 0
  --~ if(aspect > 4/3) then
    --~ s = h/768
    --~ x = math.floor((w-1024*s)/2)
  --~ else
    --~ s = w/1024
    --~ y = math.floor((h-768*s)/2)
  --~ end
  --~ return s, x, y
--~ end
--~ screen_scale, x_screen_scale, y_screen_scale = getScale(C.getWindowWidth(), C.getWindowHeight())

--~ lastResetTime = C.getTime() /1000

--~ local sW, sH = C.getWindowWidth(), C.getWindowHeight()

--~ lQuery.onresize(function(w, h)
	--~ screen_scale, x_screen_scale, y_screen_scale = getScale(w,h)
	--~ sW, sH = w, h
	--~ if lastResetTime + 0.5 < time then
		--~ lastResetTime = time
	--~ end
--~ end)

--~ lQuery.getMouseXY = function() 
	--~ return (C.getMouseX() - x_screen_scale)/screen_scale, (C.getMouseY() - y_screen_scale)/screen_scale
--~ end

--~ lQuery.addhook(function()
	--~ if lastResetTime + 0.5 < time then 
		--~ C.init('Long backgammon game', sW, sH, 32, 'vr')
	--~ end
	--~ C.reset() -- сброс координат
	--~ C.move(x_screen_scale, y_screen_scale)
  --~ C.scale(screen_scale, screen_scale)
  --~ C.clear()
--~ end)

--~ C.print = function(font, text, width, align)
	--~ C.push()
	--C.move(math.floor(x_screen_scale*screen_scale), math.floor(y_screen_scale*screen_scale))
	--~ C.scale(1/screen_scale, 1/screen_scale)
	--~ C.move(-(x_screen_scale), math.floor(y_screen_scale*screen_scale))
	--~ C.move(math.floor(x_screen_scale*screen_scale), math.floor(y_screen_scale*screen_scale))
	--~ fodnt:select()
	--~ C.fontPrint(text, width * screen_scale or 10000, align or 1)
	--~ C.pop()
--~ end

local computer = 1 --комп играет черными

--доска
local board = E:new(screen)

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
E:new(board):image('data/bg1.png'):move(167,16)
local shadows = E:new(board) --тени
E:new(board):image('data/bg.png')

local chip = C.resLoader('data')

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
			chip.shadow:draw()
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
local game
local game_old

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
		E:new(allowedMoves):image(chip.highlight):move(getChipXY(pos)):set({a = 127, pos = pos, count = v[2], pointer = v[1], lvl = lvl}):size(45,45)
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

--функция перемещения фишки
local chipAnimTable = {speed = delayMove, queue = 'move', callback = function(s)
	s:stop('shadow'):animate({shadow = 0}, {'shadow', speed = 0.7})
end}
chips = E:new(board)
local function moveChip(chip, pos, check)
	if not chip then 
		print('moveChip error: chip is nil')
		return false 
	end
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
			:stop('shadow'):animate({shadow = 5}, 'shadow')
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
		chip.button:draw()
		C.setBlendMode(C.blendAdditive)
		C.Color(255,255,255, (s._opacity + (lQuery.MousePressedOwner == s and 70 or 0)) * s._active / 105)
			chip.button:draw()
		C.pop() C.push() --рестарт матрицы
		C.move(s.x + (lQuery.MousePressedOwner == s and 1 or 0), s.y+8 + (lQuery.MousePressedOwner == s and 1 or 0))
		C.setBlendMode(C.blendAlpha)
		C.Color(150+s._active,150+s._active,150+s._active,255)
		Fonts["Tahoma"][10]:print(s._text, 152, 0)
	end):mouseover(function(s)
		s:stop('fade'):animate({_opacity = 70}, 'fade') 
	end):mouseout(function(s)
		s:stop('fade'):animate({_opacity = 0}, {speed = 1, queue = 'fade'})
	end):size(chip.button.w, chip.button.h)
	e.deactivate = function(s)
		s:stop('active'):animate({_active = 0}, 'active')
	end
	e.activate = function(s)
		s:stop('active'):animate({_active = 105}, 'active')
	end
	return e
end

local AIweights = require 'data.ai.default'
local AIaddWeights = {}
local AImyLast --моя последняя фишка
local AIenemyTopPos, AIenemyBottomPos
local AImoves --здесь хранится цепочка самого длинного хода
local AImovesBuf = {}
local sqr = math.sqrt
--прогоняет цикл в относительных координатах (для белых это ничего не меняет)
local function AIloop(player, i)
	if player == 2 then
		if i < 13 then
			return i + 12
		else
			return i - 12
		end
	end
	return i
end

local function sixInRow() --проверка на забивание 6 подряд, true если ход возможен
	local player = game.player
	local secondPlayer = player == 1 and 2 or 1
	if game.last[secondPlayer] > 18 then return true end
	local count = 1
	local b = board.a
	local bb
	local prev = 0
	for i = game.last[secondPlayer], 24 do
		bb = b[AIloop(secondPlayer, i)]
		if bb.player == player then
			if bb.player == prev then
				count = count + 1
				if count == 6 then return false end
			end
		else
			count = 1
		end
		prev = bb.player
	end
	return true
end

local throwMove = nil
local function canThrow(pos, player, move)
	local t = true --эта фишка последняя?
	for i = 1, 5 do
		if board.a[pos-i].player == player then
			t = false
			break
		end
	end
	throwMove = pos + (player - 1) * 12 + move + player - 1
	if t and throwMove > 24 + player then 
		throwMove = 24 + player --так надо
	end
	if throwMove == 24 + player then return true end
	throwMove = nil
	return false
end

--оценочная функция, вызываем её только на листьях чтобы сэкономить время
--(важен только коненчный результат)
local function AIWeightFunc()
	local aw = AIweights --веса
	local b = board.a
	local player = game.player
	local score, prev, last, subhole, holes, pair = 0,0,0,0,0,0
	local first, i, i2, has, buf
	local hasInHome = false
	local secondPlayer = player == 1 and 2 or 1
	local bb = b[AIloop(secondPlayer, 1)]
	local gameStart = bb.chips > 2 and bb.player == secondPlayer --если на голове больше 3 - начало игры
	bb = b[AIloop(player, 1)] --первая
	if bb.chips > 1 then score = score - aw.head * bb.chips end --за снятие с головы
	local startChips = bb.chips
	local countInHome = 0
	local secondFirst = game.first[secondPlayer]
	for k = 1, 24 do
		if k == 13 then prev = 0 end --так как в этом месте для соперника по сути разрыв
		i = AIloop(player, k)
		i2 = AIloop(secondPlayer, k)
		bb = b[i]
		if bb.player == player then
			score = score + aw.holes * subhole * (subhole + 2) --если очень большая дырка
			subhole = 0
			last = k --где стоит последняя фишка
			if not first then --где стоит первая
				first = k
			end
			if k < 7 then --если есть на первых семи клетках (голова)
				hasInHome = true
			end
			buf = aw.fill + bb.chips * aw.tower --бонус за заполнение и постройку башен
			if k < 19 then --для всех фишек не дома
				if first then
					buf = buf / 100
				end
				if i2 > secondFirst then
						score = score + buf
				else
					score = score + buf/100
				end
				score = score + aw.nearHome * bb.chips * k
			else
				if first < 19 and not gameStart then --специальный бонус, чтобы не двигал в доме фишки
					score = score + bb.chips * (k-19) * aw.movInHome
				end
				if first > 18 or k > AIenemyTopPos then 
					score = score + buf
				else
					score = score + buf/10
				end
				countInHome = countInHome + bb.chips
			end
			if gameStart then
				score = score + aw.field_start[k]
			else
				score = score + aw.field_middle[k]
			end
			if k ~= first and i2 > secondFirst and k ~= 12 and (game.last[player] > k) then
				--вес за закрытие опасных клеток
				--чем больше наших фишек стоит  перед опасным участком тем быстрее его нужно забить
				score = score + AIaddWeights[k] * AIaddWeights[k] * (startChips > 7 and 0.04 or 0.15)
				if AIaddWeights[k] > 3 then score = score + sqr(bb.chips)/5 end
			end
		else
			if first and i2 > secondFirst then subhole = subhole + 1 end
		end
		if prev == player and i2 > secondFirst then
				pair = pair + 1
		else
			if pair > 0 then
				score = score + pair * pair * (hasInHome and aw.pair or aw.pair_end) + k*0.01
			end
			pair = 0
		end
		prev = bb.player
	end
	if last > 18 then
		last = 18
	end
		if not hasInHome and countInHome < 15 and first and last then
			score = score + (last - first) * aw.length
		end
	if hasInHome then
		if gameStart then score = score + countInHome * aw.home
		else score = score + countInHome * aw.home_middle end
	else
		score = score + countInHome * aw.home_end
	end
	
	score = score + b[24+player].chips * aw.throw --вес за сброшенные фишки
	return score
end

--построение дерева возможных ходов
local double, AIBestScore
local function generateMoves(lvl, head, taken_from_head, ar)
	local b = board.a
	local bb, ch, from_head, isInHome, pos, score
	local leaf = true
	if lvl > maxChain then maxChain = lvl end
	if lvl > 4 then return true end
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
					--~ print(string.rep("    ", lvl-1) .. i .. " - " .. currMove)
				--~ if sixInRow(loop(i + currMove)) then --правило забивания шести
					if not ar[i] then ar[i] = {} end
					pos = #ar[i]+1
					--для экономии места, здесь это клетка, куда попадет фишка
					score = throwMove or loop(i + currMove)
					ar[i][pos] = {{}, currMove, score, 0}
					table.insert(AImovesBuf, i)
					table.insert(AImovesBuf, score)
					leaf = false
					if not double then moves[k] = 0 end
					if generateMoves(lvl + 1, 
						head or ch.head and from_head, 
						from_head and taken_from_head + 1 or taken_from_head, 
						ar[i][pos][1], 
						currMove) then
							--это лист, тут выполняем оценочную функцию
							if sixInRow() then
								if game.player == computer then 
									score = AIWeightFunc()
									ar[i][pos][4] = score
									if score > AIBestScore then
										AIBestScore = score
										AImoves = table.copy(AImovesBuf)
									end
								end
							else
								table.remove(ar[i], pos)
							end
					end
					table.remove(AImovesBuf)
					table.remove(AImovesBuf)
					if not double then moves[k] = currMove end
				--~ end
					moveChip(ch, i, true)
				end
				end
			end
		end
		end
	end
	return leaf
end

local function boardPrepass()
	local player_1_throw, player_2_throw = true, true
	local b, bb
	local ba = board.a
	local player = game.player
	AIenemyBottomPos = 0
	AIenemyTopPos = 25
	local prev = 0
	local pairPos = 0
	local pairCount = 0
	local secondPlayer = player == 1 and 2 or 1
	if not game.last then game.last = {0,0} end
	if not game.first then game.first = {25,25} end
	game.last[1] = 0
	game.last[2] = 0
	game.first[1] = 25
	game.first[2] = 25
	game.inhome[1] = 0
	game.inhome[2] = 0
	for i = 1, 24 do
		b = ba[i]
		k = AIloop(player, i)
		bb = ba[k]
		--сложный алгоритм, вычисляет веса на основе цепочек противника
		AIaddWeights[i] = 0
		if bb.player ~= secondPlayer then
			pairCount = 0
			if i < 24 then 
				for j = i+1, 24 do
					if ba[AIloop(player, j)].player == secondPlayer then
						pairCount = pairCount + 1
					else break end
				end
			end
			if i > 1 then
				for j = i-1, 1, -1 do
					if ba[AIloop(player, j)].player == secondPlayer then
						pairCount = pairCount + 1
					else break end
				end
			end
			if pairCount > 1 then
				AIaddWeights[i] = pairCount
			end
		end
		if b.chips > 0 then
			game.last[b.player] = math.max(AIloop(b.player, i), game.last[b.player])
			game.first[b.player] = math.min(AIloop(b.player, i), game.first[b.player])
		end
		if bb.player == secondPlayer then
			if i > 12 and AIenemyTopPos > i then AIenemyTopPos = i end
			if i < 13 and AIenemyBottomPos < i then AIenemyBottomPos = i end
		elseif bb.player == player then
			AImyLast = i
		end
		if AIloop(1, i) > 18 then if b.player == 1 then game.inhome[1] = game.inhome[1] + b.chips end end
		if AIloop(2, i) > 18 then if b.player == 2 then game.inhome[2] = game.inhome[2] + b.chips end end
	end
	game.inhome[1] = game.inhome[1] + ba[25].chips
	game.inhome[2] = game.inhome[2] + ba[26].chips
	--~ table.print(AIaddWeights)
end

--поднимаем фишку вверх над остальными
local function chipUp(c)
	for k, v in ipairs(chips._child) do
		if v == c then table.remove(chips._child, k) break end
	end
	table.insert(chips._child, c)
end

local AIqueue = E:new(screen)
AIqueue.b = board
AIqueue.ds = dice
local function AI()
	local b = board.a
	if maxChain > 1 then 
		AIqueue.moves = AImoves
		local i = 1
		while i < #AImoves do
			local ii = i
				AIqueue:delay({speed = delayComputerMove, cb = function(s)
					local c = table.last(s.b.a[s.moves[ii]].top)
					chipUp(c)
					moveChip(c, s.moves[ii+1])
				end})
			i = i + 2
		end
	end
	AIqueue:delay({speed = delayBetweenMoves, cb = function(s)
		s.ds.roll()
	end})
end

--кнопки
local endTurn = E:new(board):keypress(function(s, key)
	if key == 'space' then
		if s._active > 0 then s:click() end
	end
end)
local undo = E:new(board):keypress(function(s, key)
	if key == 'u' then
		if s._active > 0 then s:click() end
	end
end)

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
		--костыль для бага с выкидыванием. Что поделать
		if dice.d1 > dice.d2 then
			moves = {dice.d1,dice.d2}
		else
			moves = {dice.d2,dice.d1}
		end
		double = false
	end
	movesTree = {}
	maxChain = 0
	moveDepth = 1
	AIBestScore = -10000
	if compVsComp then computer = game.player end
	boardPrepass() --предпроход доски - нужно для выполнения некоторых проверок
	generateMoves(1, false, 0, movesTree, 0)
	movPointer = movesTree
	game.first_move[game.player] = false
	game.allow_two_from_head = false
	if computer == game.player then --запуск ИИ
		AI()
	else
		if maxChain == 1 then endTurn:activate() end
	end
	--~ print('======================= '.. dice.d1 .. ' - '..dice.d2 ..' ============================')
	--~ table.print(movesTree)
	--~ table.print(AImoves)
end

local diceLog = assert(io.open('dice.log', "a"))
dice.roll = function() --бросок кубиков
	if compVsComp then computer = game.player end
	if endTurn._active > 0 or computer == game.player or editmode then 
		if board.a[25].chips == 15 then print 'White wins!' return end
		if board.a[26].chips == 15 then print 'Black wins!' return end
		game_old = table.copy(game)
		dice.d1 = math.random(1, 6)
		dice.d2 = math.random(1, 6)
		--~ dice.d1=6
		--~ dice.d2=2
		diceLog:write(dice.d1, ' ', dice.d2, "\n")
		doRoll()
	end
end

local function loadGame(name)
	local s = require(name)
	local p = {1, 1}
	local c, x, y
	for _, v in ipairs(chips._child) do
		v:stop()
	end
	AIqueue:stop():delay(delayMove + 0.2)
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
end
E:new(board):button('Load'):move(7, 600):click(function() --загрузка
	loadGame('save.game')
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

--подсказка, показывающая сколько кубиков соответствует ходу
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

local function makeUndo(c)
	undo:activate()
	table.insert(undo.u, {c, c.pos, movPointer, moveDepth})
end
local function checkChain()
	if moveDepth == maxChain then endTurn:activate() end
end
local function movedblClick(c, ismax)
	if #allowedMoves._child > 0 then
		local v, p, bestpos
		for _, vv in ipairs(allowedMoves._child) do
			p = AIloop(game.player, vv.pos)
			if vv.pos > 24  and ismax then v = vv break end
			if not v or (p > bestpos and ismax or p < bestpos and not ismax) then
				v = vv
				bestpos = p
			end
		end
		makeUndo(c)
		moveChip(c, v.pos)
		movPointer = v.pointer
		moveDepth = moveDepth + v.lvl
		allowedMoves._child = {}
		checkChain()
	end
end
local function chipBack(c)
	local b = board.a[c.pos]
	b.chips = b.chips - 1
	x, y = getChipXY(c.pos)
	c:stop('move'):animate({x = x, y = y}, 'move')
	b.chips = b.chips + 1
end
local function isChipInTop(chip)
	return chip.pos ~= 0 and table.last(board.a[chip.pos].top) == chip and (chip.player == game.player or editmode)
end
local function initChips(color, offsetx, offsety)
	for i = 0, 14 do
		local ch = E:new(chips):move(offsetx, offsety):size(board.chip_size,board.chip_size)
		--перегрузка стандартного Drag'n'Drop движка
		:mousepress(function(c, x, y, button)
			if #c._animQueue.move == 0 and button == 'l' then
				if isChipInTop(c) then
					chipUp(c)
					c:stop('move')
					c:stop('shadow'):animate({shadow = 7}, 'shadow')
					lQuery.drag_start(c, x, y)
				end
				c._ox = c.x
				c._oy = c.y
			end
		end)
		:dblclick(movedblClick)
		:mouserelease(function(c, x, y, button)
			if editmode then
				lQuery.drag_end(c)
				local bestdist = 999999999
				local x, y, dist, bestpos
				if c._ox ~= c.x or c._oy ~= c.y then
					for i = 1, 26 do
						x, y = getChipXY(i)
						dist = (x - c.x)*(x - c.x) + (y - c.y)*(y - c.y)
						if dist < bestdist and (board.a[i].player == c.player or board.a[i].player == 0) then 
							bestdist = dist bestpos = i 
						end
					end
					if bestpos ~= c.pos then 
						moveChip(c, bestpos)
					else
						chipBack(c)
					end
				end
				return
			end
			if isChipInTop(c) then
				if button == 'l' or lQuery._drag_object == c then 
					lQuery.drag_end(c)
					if c._ox ~= c.x or c._oy ~= c.y then
						local bestpos, bestv = getBestDist(c.x, c.y)
						if bestpos then
							makeUndo(c)
							moveChip(c, bestpos)
							movPointer = bestv.pointer
							moveDepth = moveDepth + bestv.lvl
							allowedMoves._child = {}
							checkChain()
						else
							chipBack(c)
						end
						if #allowedMoves._child == 0 then genMoves(c) end
					else
						allowedChildFadeout()
					end
					chiptip:stop():animate({a = 0})
					c:stop('shadow'):animate({shadow = 0.01}, {queue = 'shadow', speed = 1})
				elseif button == 'r' then
					movedblClick(c, true)
				elseif button == 'm' then
					movedblClick(c)
				end
			end
		end)
		:set({img = color, highlight = 0, player = color, 
		pos = 0, shadow = 0, head = true, 
		_drag_callback = function(s) --при перемещении прилипаем к наиболее подходящему ходу
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
						if v ~= bestv and v._hover == true then
							v._hover = false
							v:stop():animate({a = 127})
						end
					end
				end
			else
				allowedChildFadeout()
			end
		end})
		:draw(function(s)
			local cs = board.chip_size
			--~ C.push()
			if s.shadow > 0 then
				C.pop()C.push()
				local x, y = s.x - shadowOff + s.shadow, s.y - shadowOff + s.shadow
				C.translateObject(x, y, math.atan((-64-x)/(y))/math.pi*180+45, 64, 64, 32, 32)
				C.Color(255,255,255,math.min(s.shadow*255/3,255))
				chip.shadow:draw()
				C.pop()C.push()
				C.translateObject(s.x, s.y, s.angle, s.w, s.h, s.ox, s.oy)
			end
			C.Color(255,255,255,255)
			chip.checkers:drawq(s.qx, s.qy, 64, 64)
			C.pop()C.push()
			C.translateObject(s.x, s.y, math.atan((-64-s.x)/(s.y))/math.pi*180+45, s.w, s.h, s.ox, s.oy)
			C.setBlendMode(C.blendDetail)
			chip.spec:draw()
			if s.highlight > 0 then 
				C.setBlendMode(C.blendAdditive)
				C.Color(255,255,255,s.highlight)
				chip.checkers:drawq(s.qx, s.qy, 64, 64)
			end
			C.setBlendMode(0) --alpha
		end)
		:mouseover(function(chip)
			if isChipInTop(chip) and computer ~= game.player and not editmode then
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

initChips(1, board.offsets[1], board.offsets[2])
initChips(2, board.offsets[5], board.offsets[6])

--сброс фишек к начальным позициям для начала новой игры
local function resetChips()
	local ba = board.a
	for i = 1, 26 do
		ba[i].chips = 0
		ba[i].player = 0
		ba[i].top = {}
	end
	for i, v in ipairs(chips._child) do
		v:stop()
		v.head = true
		v.pos = 0
		if v.player == 1 then
			moveChip(v, 1)
		else
			moveChip(v, 13)
		end
	end
	
	game = {
		player = math.random(1,2), --кто ходит 1 или 2
		first_move = {true, true}, --первый/второй игрок ходит первый раз
		allow_two_from_head = false,
		throw = {false, false}, --первый/второй игрок может скидывать
		inhome = {0,0}, --сколько в доме
		row = {false, false}, --первый/второй игрок может выстроить ряд из шести
		moves = {}, --просто список ходов
		last = {1,1},
		first = {25,25}
	}
	AIqueue:stop():delay(delayMove + 0.2)
	dice.roll()
end

resetChips()

E:new(board):button('New game'):move(7, 560):click(function()
	resetChips()
end):activate()

--просто вывод фпс
local smallFont = Fonts["Tahoma"][8]
E:new(screen):draw(function()
	smallFont:print("fps: " .. math.floor(C.FPS) .. ", mem: " .. gcinfo(), 100, 0)
end):move(0,768-12)

--обработчик нажатий клавиш
E:new(screen):keypress(function(s, key)
	if key == 'e' then
		if editmode then 
			doRoll() 
			editmode = false
		else
			game.player = game.player == 1 and 2 or 1
			editmode = true
		end
	elseif key == '1' and editmode then
		game.player = 2
	elseif key == '2' and editmode then
		game.player = 1
	elseif key == 'd' and editmode then
		dice.d1 = math.random(1,6)
		dice.d2 = math.random(1,6)
	end
end)
if tests then
	compVsComp = true
	C.fileEach('tests', function(name)
		ext = C.fileExt(name)
		if ext ~= 'lua' then return end
		i = C.fileName(name)
		loadGame('tests.'..i)
		if makeAns then
			C.putFile('tests/'..i..'.ans', table.concat(AImoves))
		else
			print(i, table.concat(AImoves) == C.getFile('tests/'..i..'.ans'))
		end
	end)
else
	C.mainLoop()
end
diceLog:close()
