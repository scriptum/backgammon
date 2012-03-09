require 'lib.cheetah'
require 'lib.lquery.init'
local C = cheetah
C.init('Long backgammon game', 1024, 768, 32, 'v')

math.randomseed(os.time())

local fast = true
local compVsComp = true

--~ local tests = true
--~ local makeAns = true

--~ if not tests then
	--~ C.init('Long backgammon game', 1024, 768, 32, 'v')
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

computer = 1 --комп играет черными

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

local smallFont = Fonts["Tahoma"][8]

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

local chip = C.resLoader('data')

E:new(board):image(chip.bg1):move(167,16)
local shadows = E:new(board) --тени, специально доска разделена на три слоя, чтобы рисовать тени правильно
E:new(board):image(chip.bg)

local shadowOff = 9
for i = 1, 30 do
	E:new(shadows):draw(function(s)
		local c = chips._child[i]
		--if c.shadow == 0.01 then c.shadow = 0 end
		if c.shadow < 3 then
			local x, y = c.x - shadowOff,c.y - shadowOff
			--геометричести правильная тень следует за источником
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
end)
:move(10, 20)
:size(70,70)
:wheel(function(s, x, y, w)
	if editmode then
		local step, a
		if w == 'u' then step = 1
		else step = -1
		end
		a = ((s.d1-1) * 6 + s.d2 - 1 + step) % 36
		s.d1, s.d2 = math.floor(a/6) + 1, a % 6 + 1
	end
end)

--подключаем правила игры с ИИ
local AI = require 'rules.long.ai'


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
--генерирует и подсвечивает возможные ходы, когда игрок берет фишку
local allowedMoves = E:new(board)
allowedMoves._child = {}
function addAllowedMove(v, lvl)
	if AI.maxChain > #allowedMoves._child then
		E:new(allowedMoves):image(chip.highlight):move(getChipXY(v[3])):set({a = 127, pos = v[3], count = v[2], pointer = v[1], lvl = lvl}):size(45,45)
	end
end

local s
local movesTree
local movPointer --указатель на участок дерева, с которого начинать движение
local function genMoves(ch, pos, ptr, lvl) --генерирует возможные ходы TODO: отсечение неполных ходов
	if not ptr then ptr = movPointer end
	if not lvl then lvl = 1 end
	if not pos then pos = ch.pos end
	local a = ptr[pos]
	if not a then return end
	local newpos
	for k, v in ipairs(a) do
		newpos = v[3]
		addAllowedMove(v, lvl)
		if v[1][newpos] then
			genMoves(ch, newpos, v[1], lvl + 1)
		end
	end
end

--массив шашек
chips = E:new(board)
--функция перемещения фишки
local chipAnimTable = {speed = delayMove, queue = 'move', callback = function(s)
	s:stop('shadow'):animate({shadow = 0}, {'shadow', speed = 0.7})
end}
function moveChip(chip, pos, check)
	if not chip then 
		print('moveChip error: chip is nil')
		return false 
	end
	if pos == chip.pos then return false end
	local b = board
	if AI.canPlace(chip, pos) then
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

--поднимаем фишку вверх над остальными
local function chipUp(c)
	for k, v in ipairs(chips._child) do
		if v == c then table.remove(chips._child, k) break end
	end
	table.insert(chips._child, c)
end

local function moveSum(s, e)
	local p = game.player
	if e > 25 then e = 25 end
	if game.player == 1 then return e - s end
	if e == 25 then return e - s - 12 end
	return AI.loop(2, e) - AI.loop(2, s)
end

local AIqueue = E:new(screen)
AIqueue.b = board
AIqueue.ds = dice
local AImovesum
local function doAI()
	local b = board.a
	if AI.maxChain > 1 then 
		AIqueue.moves = AI.moves
		table.insert(game.moves, {dice.d1, dice.d2})
		local p = #game.moves
		local i = 1
		while i < #AI.moves do
			local ii = i
				AIqueue:delay({speed = delayComputerMove, cb = function(s)
					local c = table.last(s.b.a[s.moves[ii]].top)
					chipUp(c)
					moveChip(c, s.moves[ii+1])
				end})
				table.insert(game.moves[p], AI.moves[i])
				table.insert(game.moves[p], AI.moves[i+1])
				AImovesum = AImovesum + moveSum(AI.moves[i], AI.moves[i+1])
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

local counters = E:new(screen):draw(function(s)
	smallFont:print("White score: "..s.wh.."\nBlack score: "..s.bl..
	"\n\nWhite distance:"..s.wm.."\nBlack distance: "..s.bm, 100, 2)
end):move(5,100)

local function doRoll()
	game.player = game.player == 1 and 2 or 1
	undo:deactivate()
	undo.u = {}
	endTurn:deactivate()
	movesTree = {}
	if dice.d1 == dice.d2 then
		moves = {dice.d1}
	else
		--костыль для бага с выкидыванием. Что поделать
		if dice.d1 > dice.d2 then
			moves = {dice.d1,dice.d2}
		else
			moves = {dice.d2,dice.d1}
		end
	end
	movesTree = {}
	AI.maxChain = 0
	AImovesum = 0
	moveDepth = 1
	if compVsComp then computer = game.player end
	AI.boardPrepass() --предпроход доски - нужно для выполнения некоторых проверок
	AI.generateMoves(1, false, 0, movesTree, 0)
	movPointer = movesTree
	if computer == game.player then --запуск ИИ
		doAI()
	else
		if AI.maxChain == 1 then endTurn:activate() end
	end
	--~ print('======================= '.. dice.d1 .. ' - '..dice.d2 ..' ============================')
	--~ table.print(movesTree)
	--~ table.print(AI.moves)
end

local diceLog = assert(io.open('dice.log', "a"))
local game_old
dice.roll = function() --бросок кубиков
	if compVsComp then computer = game.player end
	if endTurn._active > 0 or computer == game.player or editmode then 
		local ba = board.a
		if not (ba[1].chips == 15 and ba[13].chips == 15) then --не первый ход
			local a
			local b = 0
			table.insert(game.moves, {dice.d1, dice.d2})
			local i = #game.moves
			if computer ~= game.player then
				for _, v in ipairs(undo.u) do
					table.insert(game.moves[i], v[2])
					table.insert(game.moves[i], v[5])
					b = b + moveSum(v[2], v[5])
				end
			else
				b = AImovesum
			end
			if dice.d1 == dice.d2 then
				a = dice.d1 * 4
			else
				a = dice.d1 + dice.d2
			end
			if game.player == 1 then
				counters.wh = counters.wh + a
				counters.wm = counters.wm - b
			else
				counters.bl = counters.bl + a
				counters.bm = counters.bm - b
			end
		end
		if ba[25].chips == 15 then print 'White wins!' return end
		if ba[26].chips == 15 then print 'Black wins!' return end
		game_old = table.copy(game)
		dice.d1 = math.random(1, 6)
		dice.d2 = math.random(1, 6)
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

local function makeUndo(c, pos, count)
	undo:activate()
	table.insert(undo.u, {c, c.pos, movPointer, moveDepth, pos, count})
end
local function checkChain()
	if moveDepth == AI.maxChain then endTurn:activate() end
end
local function movedblClick(c, ismax)
	if #allowedMoves._child > 0 then
		local v, p, bestpos
		for _, vv in ipairs(allowedMoves._child) do
			p = AI.loop(game.player, vv.pos)
			if vv.pos > 24  and ismax then v = vv break end
			if not v or (p > bestpos and ismax or p < bestpos and not ismax) then
				v = vv
				bestpos = p
			end
		end
		makeUndo(c, v.pos, v.count)
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
							makeUndo(c, bestpos, bestv.count)
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
		v.pos = 0
		if v.player == 1 then
			moveChip(v, 1)
		else
			moveChip(v, 13)
		end
	end
	
	--массив игровых состояний
	game = {
		player = math.random(1,2), --кто ходит 1 или 2
		moves = {}, --просто список ходов
	}
	AIqueue:stop():delay(delayMove + 0.2)
	counters.bl = 0
	counters.wh = 0
	counters.bm = 360
	counters.wm = 360
	dice.roll()
end

resetChips()

E:new(board):button('New game'):move(7, 560):click(function()
	resetChips()
end):activate()

--просто вывод фпс
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
		local i = C.fileName(name)
		local a = 'tests/'..i..'.ans'
		loadGame('tests.'..i)
		if makeAns then
			C.putFile(a, table.concat(AI.moves))
		else
			if C.fileExists(a) then print(string.format('%-70s %s', i, tostring(table.concat(AI.moves) == C.getFile(a)))) end
		end
	end)
else
	C.mainLoop()
end
diceLog:close()
