local AI = {
	maxChain = 0, --максимально возможная глубина хода
	moves --здесь хранится цепочка самого длинного хода
}
local ba = board.a --импорт доски
local AIweights = require 'rules.long.ai.default'
local AIaddWeights = {}
local AImyLast --моя последняя фишка
local AIenemyTopPos, AIenemyBottomPos, gameStart, hasInHome
local AImovesBuf = {}
local AIinHome = {0,0} --сколько в доме (внутреннее)
local AIplFirst = {0,0} --где стоит первая фишка
local AIplLast = {0,0} --где стоит последняя фишка
local allowTwoHead --можно скинуть две с головы
local sqr = math.sqrt
local player --текущий игрок
local comp --каким цветом играет ИИ
local move


local canPlace = function(ch, pos) --проверяет, можно ли класть сюда фишку
	local p = ba[pos].player
	return (p == 0 or p == ch.player)
end
AI.canPlace = canPlace

local function loop(num) --зацикливает доску
	return (num - 1) % 24 + 1
end
AI.mirror = loop

--прогоняет цикл в относительных координатах (для белых это ничего не меняет)
local function AIloop(pl, i)
	if pl == 2 then
		if i < 13 then
			return i + 12
		else
			return i - 12
		end
	end
	return i
end
AI.loop = AIloop
local function sixInRow() --проверка на забивание 6 подряд, true если ход возможен
	local secondPlayer = player == 1 and 2 or 1
	if AIplLast[secondPlayer] > 18 then return true end
	local count = 1
	local bb
	local prev = 0
	for i = AIplLast[secondPlayer], 24 do
		bb = ba[AIloop(secondPlayer, i)]
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
local function canThrow(pos, pl, move)
	local t = true --эта фишка последняя?
	for i = 1, 5 do
		if board.a[pos-i].player == pl then
			t = false
			break
		end
	end
	throwMove = pos + (pl - 1) * 12 + move + pl - 1
	if t and throwMove > 24 + pl then 
		throwMove = 24 + pl --так надо
	end
	if throwMove == 24 + pl then return true end
	throwMove = nil
	return false
end

--оценочная функция, вызываем её только на листьях чтобы сэкономить время
--(важен только коненчный результат)
local function AIWeightFunc()
	local aw = AIweights --веса
	local score, prev, last, subhole, holes, pair = 0,0,0,0,0,0
	local first, i, i2, has, buf, chainDist
	local lastSecondPos = 0
	local hasDanger = false
	local secondPlayer = player == 1 and 2 or 1
	local bb = ba[AIloop(player, 1)] --первая
	if bb.chips > 1 then score = score - aw.head_mul * bb.chips * bb.chips - aw.head * bb.chips end --за снятие с головы
	local startChips = bb.chips
	local countInHome = 0
	local secondFirst = AIplFirst[secondPlayer]
	for k = 1, 24 do
		if k == 13 then prev = 0 end --так как в этом месте для соперника по сути разрыв
		i = AIloop(player, k)
		i2 = AIloop(secondPlayer, i)
		bb = ba[i]
		if bb.player == player then
			score = score + aw.holes * subhole * (subhole + 2) --если очень большая дырка
			subhole = 0
			last = k --где стоит последняя фишка
			if not first then --где стоит первая
				first = k
			end
			--это основной интеллект, данное правило решает в 99% случаев
			buf = aw.fill + bb.chips * aw.tower --бонус за заполнение и постройку башен
			if k > 12 and gameStart then
				score = score + aw.onenemybase * bb.chips --за то что фишки на базе противника
			end
			if k < 19 then --для всех фишек не дома
				if k == first and bb.chips < 3 then
					buf = buf / 10
				end
				if not gameStart then buf = buf / 2 end
				if i2 > secondFirst then
						score = score + buf
				else
					score = score + buf/100
				end
				score = score + aw.nearHome * bb.chips * k
			else
				if i2 > secondFirst then
					if gameStart then score = score + buf
					else score = score + buf/10 end
				else
					score = score + buf/100
				end
				countInHome = countInHome + bb.chips
			end
			if gameStart then
				score = score + aw.field_start[k]
			else
				score = score + aw.field_middle[k]
			end
			if k ~= AIplFirst[player] and (i2 > secondFirst or AIaddWeights[k] > 4)
					and AIplLast[player] >= k and
					(k ~= 12 or k == 12 and ba[AIloop(player, 11)].player == secondPlayer) and 
					AIaddWeights[k] > 0 then
				--вес за закрытие опасных клеток
				--чем больше наших фишек стоит  перед опасным участком тем быстрее его нужно забить
				score = score + AIaddWeights[k] * AIaddWeights[k] * (startChips > 7 and aw.danger_start or aw.danger_end)
				if AIaddWeights[k] > 3 then
					buf = 0
					for j = k + 1, k + 4 do
						if j > 24 then break end
						if ba[AIloop(player, j)].player == secondPlayer then buf = buf + 1 end
					end
					if buf == 4 then
						score = score + sqr(bb.chips*2 + AIaddWeights[k]) * aw.danger_add
						hasDanger = true
					end
				end
			end
		else
			if bb.player == secondPlayer then lastSecondPos = k end
			if first and i2 > secondFirst then subhole = subhole + 1 end
		end
		--функция оценки парных
		if bb.player == player and i2 > secondFirst --[[and (hasInHome or not hasInHome and (k < 13 or k > 18))]] then
			pair = pair + 1
		else
			chainDist = pair
			if pair > 1 and gameStart or pair > 5 and not gameStart then
				if pair >= 6 then
					pair = 10 + (pair - 5) / 100
				elseif k > 12 and k < 20 then 
					pair = pair - 2
				end
				score = score + pair * pair * aw.pair * (20 - countInHome) * 0.05 + k * 0.002
				score = score - (k - lastSecondPos - chainDist) * aw.chainDist
			end
			pair = 0
		end
		prev = bb.player
	end
	chainDist = pair
	if pair > 1 then
		k = 25
		if pair >= 6 then
			pair = 10 + (pair - 5) / 100
		elseif k > 12 and k < 20 then 
			pair = pair - 2
		end
		score = score + pair * pair * aw.pair * (20 - countInHome) * 0.05 + k * 0.002
		score = score - (k - lastSecondPos - chainDist) * aw.chainDist
	end
	if not gameStart then 
		for j = 1, #AImovesBuf, 2 do
			if AIloop(player, AImovesBuf[j]) > 18 then 
				score = score + (AIloop(player, AImovesBuf[j+1]) - AIloop(player, AImovesBuf[j])) * aw.movInHome 
			end
		end
	end
	if last > 18 then
		last = 18
	end
	if not hasInHome and countInHome < 15 and first and last then
		score = score + (last - first) * aw.length
	end
	if hasDanger then
		if countInHome > 11 then countInHome = 11 end
		countInHome = countInHome / 2
	end
	--~ if countInHome > 11 then countInHome = 11 end
	if hasInHome then
		if gameStart then score = score + countInHome * aw.home
		else score = score + countInHome * aw.home_middle end
	else
		score = score + countInHome * aw.home_end
	end
	score = score + ba[24+player].chips * aw.throw --вес за сброшенные фишки
	return score
end


--быстро считает сколько в доме фишек
local function inHome()
	local c = 0
	local b, i, j
	if player == 1 then i, j = 19, 24
	else i, j = 7, 12
	end
	for k = i, j do
		b = ba[k]
		if b.player == player then
			c = c + b.chips
		end
	end
	c = c + ba[24 + player].chips
	return c
end

--построение дерева возможных ходов
local double, AIBestScore
local function generateMoves(lvl, head, taken_from_head, ar)
	local bb, ch, from_head, pos, score
	local leaf = true
	if lvl > AI.maxChain then AI.maxChain = lvl end
	if lvl > 4 then return true end
	for k, currMove in ipairs(moves) do
		if currMove > 0 then
		for i = 1, 24 do
			bb = ba[i]
			if bb.chips > 0 then --если здесь есть фишки
				ch = table.last(bb.top)
				cp = ch.player
				throwMove = nil
				from_head = (cp == 1 and i == 1 or cp == 2 and i == 13)
				if cp == player --проверяем ходы только текущего пользователя
				and (((not (head and from_head)) --выкидываем варианты с головы, если с головы уже снимали
				or allowTwoHead and taken_from_head < 2) --за исключением частного случая - дубль в начале игры
				and (cp == 2 and (i < 13 and (i + currMove < 13) or i >12) or cp == 1 and i + currMove <= 24) --не позволять ходить кругами
				or (inHome() == 15) and canThrow(i, cp, currMove)) --скидывание
				then
				if move(ch, throwMove or loop(i + currMove), true) then --если ход возможен (пока простая проверка, отсекает очевидно невозможные варианты) - как бы делаем его и рекурсивно повторяем процесс
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
						head or from_head, 
						from_head and taken_from_head + 1 or taken_from_head, 
						ar[i][pos][1], 
						currMove) then
							--это лист, тут выполняем оценочную функцию
							if sixInRow() then
								--~ if player == comp then 
									score = AIWeightFunc()
									ar[i][pos][4] = score
									--~ if score > AIBestScore then
										--~ AIBestScore = score
										--~ AI.moves = table.copy(AImovesBuf)
									--~ end
								--~ end
							else
								table.remove(ar[i], pos)
							end
					end
					table.remove(AImovesBuf)
					table.remove(AImovesBuf)
					if not double then moves[k] = currMove end
				--~ end
					move(ch, i, true)
				end
				end
			end
		end
		end
	end
	return leaf
end
AI.generateMoves = generateMoves

--постобработка
local function boardPostpass(ptr, lvl)
	if not lvl then lvl = 2 end
	local leaf = true
	for k, v in pairs(ptr) do
		leaf = false
		table.insert(AImovesBuf, k)
		for _, vv in pairs(v) do
			table.insert(AImovesBuf, vv[3])
			if boardPostpass(vv[1], lvl + 1) then
				if vv[4] > AIBestScore and lvl == AI.maxChain then
					AIBestScore = vv[4]
					AI.moves = table.copy(AImovesBuf)
				end
			end
			table.remove(AImovesBuf)
		end
		table.remove(AImovesBuf)
	end
	return leaf
end
AI.boardPostpass = boardPostpass

local function boardPrepass()
	local player_1_throw, player_2_throw = true, true
	local b, bb
	
	--импортируем данные из доски
	player = game.player
	comp = computer
	move = moveChip
	
	if dice.d1 == dice.d2 then
		double = true
	else
		double = false
	end
	
	--проверка на возможность скидывания двух фишек с головы
	if ba[(player - 1) * 12 + 1].chips == 15 and 
	   dice.d1 == dice.d2 and 
	   (dice.d1 == 3 or dice.d1 == 4 or dice.d1 == 6) then
		allowTwoHead = true
	else allowTwoHead = false
	end

	AIenemyBottomPos = 0
	AIenemyTopPos = 25
	local prev = 0
	local pairPos = 0
	local pairCount = 0
	local secondPlayer = player == 1 and 2 or 1
	if not AIplLast then AIplLast = {0,0} end
	if not AIplFirst then AIplFirst = {25,25} end
	bb = ba[AIloop(secondPlayer, 1)]
	gameStart = bb.chips > 2 and bb.player == secondPlayer --если на голове больше 3 - начало игры
	hasInHome = false
	AIplLast[1] = 0
	AIplLast[2] = 0
	AIplFirst[1] = 25
	AIplFirst[2] = 25
	AIinHome[1] = 0
	AIinHome[2] = 0
	AIBestScore = -10000
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
			AIplLast[b.player] = math.max(AIloop(b.player, i), AIplLast[b.player])
			AIplFirst[b.player] = math.min(AIloop(b.player, i), AIplFirst[b.player])
		end
		if bb.player == secondPlayer then
			if i > 12 and AIenemyTopPos > i then AIenemyTopPos = i end
			if i < 13 and AIenemyBottomPos < i then AIenemyBottomPos = i end
		elseif bb.player == player then
			AImyLast = i
			if i < 7 then --если есть на первых семи клетках (голова)
				hasInHome = true
			end
		end
		if AIloop(1, i) > 18 then if b.player == 1 then AIinHome[1] = AIinHome[1] + b.chips end end
		if AIloop(2, i) > 18 then if b.player == 2 then AIinHome[2] = AIinHome[2] + b.chips end end
	end
	AIinHome[1] = AIinHome[1] + ba[25].chips
	AIinHome[2] = AIinHome[2] + ba[26].chips
	--~ table.print(AIaddWeights)
end
AI.boardPrepass = boardPrepass

return AI
