
local pairs, print, table= pairs, print, table

local utils = require 'metrics.utils'
local HG = require 'hypergraph'
local keys = (require 'metrics.rules').rules

hypergraph = hypergraph or HG.H{}
local graph = hypergraph

module ('metrics.captures.hypergraph')

function getHyperGraphNodeFromNode(node)
	if node.hypergraphnode then return node.hypergraphnode end

	local hypergraphnode = HG.N(node.tag or 'unknown')
	hypergraphnode.nodeid = node.nodeid;
	hypergraphnode.data = node
	
	node.hypergraphnode = hypergraphnode

	return hypergraphnode
end

function getCallerCalee(masterNode, functionName)

	local returnValues = {}

	for k,v in pairs(masterNode.metrics.functionExecutions[functionName] or {}) do
		--print ('Call node', v.tag, v.nodeid, v.text)

		-- find caller function

		local parent = v.parent

		while (parent ~= nil and parent.tag ~= 'GlobalFunction' and parent.tag ~= 'LocalFunction' and parent.tag ~= 'Function') do
			--print ('', parent.tag)
			parent = parent.parent
		end

		if (parent ~= nil) then
			-- found enclosing function
			--print ('Caller function', parent.tag, parent.nodeid,  parent.name)
		end


		local calee 

		for i,j in pairs(masterNode.metrics.functionDefinitions) do
			if (j.name == functionName) then
				calee = j
			end		
		end

		if (calee ~= nil) then
			--print ('Callee function', calee.tag, calee.nodeid,  calee.name)
		end
	
		table.insert(returnValues, {v, parent, calee})

	end
	return returnValues
end

function normalProcessNode(data) 
	local currentHyperNode = getHyperGraphNodeFromNode(data);
	
	local treeRelationEdge = HG.E'treerelation'
	graph[treeRelationEdge] = { [HG.I'parent'] = currentHyperNode }
	for _, child in pairs(data.data or {}) do
		graph[treeRelationEdge][HG.I'child'] = getHyperGraphNodeFromNode(child)
	end

	local stat = findStatementForNode(data)
	if stat ~= nil then
			local order = 0
			local edge = HG.E'executes'
			edge.type = 'statement'
			graph[edge] = { [HG.I'executor'] = currentHyperNode }
			for _, used_node in pairs(stat) do
				order = order + 1
				local node = getHyperGraphNodeFromNode(used_node)
				node.statementExecuteOrder = order
				graph[edge][HG.I'statement'] = node
			end
	end
	
	local edge = HG.E'measures'
	local metric_i = HG.I'metric'
	edge.type = 'loc'
	edge.description = 'lines of code metric'
	metric_i.type = 'loc'
	metric_i.description = 'lines of code metric'
	graph[edge] = { [HG.I'subject'] = currentHyperNode, [metric_i] = getHyperGraphNodeFromNode(data.metrics.LOC) }

	if data.tag == 'Block' or data.tag == 'STARTPOINT' then
		local edge = HG.E'defines'
		edge.type = 'function'
		edge.description = 'defines a function'
		graph[edge] = { [HG.I'definer'] = currentHyperNode }

		for _, functionNode in pairs(data.metrics.blockdata.fundefs) do
			graph[edge][HG.I'function'] = getHyperGraphNodeFromNode(functionNode)
		end
		
		for _ , variable in pairs(data.metrics.blockdata.locals_total) do
			local edge = HG.E'uses'
			edge.type = 'local_variable'
			edge.description = name
			graph[edge] = { [HG.I'user'] = currentHyperNode, [HG.I'local_variable'] = getHyperGraphNodeFromNode(variable[2][1]) }
			for _ , occurence in pairs(variable[2]) do
				graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
			end
		end
					
		for name, occurences in pairs(data.metrics.blockdata.remotes) do
			local edge = HG.E'uses'
			edge.type = 'remote_variable'
			edge.description = name
			graph[edge] = { [HG.I'user'] = currentHyperNode, [HG.I'remote_variable'] = getHyperGraphNodeFromNode(utils.getVariableCommonPoint(occurences[1],name)) }
			for _ , occurence in pairs(occurences) do
				graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
			end
		end
		
		for _, variableInstance in pairs(data.metrics.blockdata.locals) do	
			local name = variableInstance[1]
			local occurences = variableInstance[2]	
			local edge = HG.E'defines'
			edge.type = 'variable'
			edge.description = name
			graph[edge] = { [HG.I'definer'] = currentHyperNode }
			for _, occurence in pairs(occurences) do
				graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
			end
		end
		
	end
		
	return data 
end

function findStatementForNode(node)
	local stats = {}
	
	for _, child in pairs(node.data or {}) do
		if child.tag ~= 'Stat' and child.tag ~= 'LastStat' then
			local stats2 = findStatementForNode(child)
			for k, v in pairs(stats2) do table.insert(stats, v) end
		else
			if child.tag == 'LastStat' then 
				table.insert(stats, child);
			else
				table.insert(stats, child.data[1])
			end
		end
	end

	return stats
end

function processFunction(funcAst)
	local funcHyperNode = getHyperGraphNodeFromNode(funcAst);
	local functionBlock = utils.searchForTagItem_recursive('Block', funcAst, 2) 
	
	local edge = HG.E'measures'
	local metric_i = HG.I'metric'
	edge.type = 'infoflow'
	edge.description = 'information flow metric'
	metric_i.type = 'infoflow'
	metric_i.description = 'information flow metric'
	graph[edge] = { [HG.I'subject'] = funcHyperNode, [metric_i] = getHyperGraphNodeFromNode(funcAst.metrics.infoflow) }
	for _, used_node in pairs(funcAst.metrics.infoflow.used_nodes) do
		graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(used_node)
	end	
	
	for _ , variable in pairs(functionBlock.metrics.blockdata.locals_total) do
		local edge = HG.E'uses'
		edge.type = 'local_variable'
		edge.description = name
		graph[edge] = { [HG.I'user'] = funcHyperNode, [HG.I'local_variable'] = getHyperGraphNodeFromNode(variable[2][1]) }
		for _ , occurence in pairs(variable[2]) do
			graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
		end
	end
					
	for name, occurences in pairs(functionBlock.metrics.blockdata.remotes) do
		local edge = HG.E'uses'
		edge.type = 'remote_variable'
		edge.description = name
		graph[edge] = { [HG.I'user'] = funcHyperNode, [HG.I'remote_variable'] = getHyperGraphNodeFromNode(utils.getVariableCommonPoint(occurences[1],name)) }
		for _ , occurence in pairs(occurences) do
			graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
		end
	end

	for _, variableInstance in pairs(functionBlock.metrics.blockdata.locals) do	

		local name = variableInstance[1]
		local occurences = variableInstance[2]	
		local edge_defines = HG.E'defines'
		edge_defines.type = 'variable'
		edge_defines.description = name
		graph[edge_defines] = { [HG.I'definer'] = funcHyperNode }
		for _, occurence in pairs(occurences) do
			graph[edge_defines][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
		end
					
	end
	
end

captures = (function()
	local key,value
	local new_table = {}
	for key,value in pairs(keys) do
		new_table[key] = normalProcessNode
	end
	
	new_table[1] = function (node) 

		local hypernode = getHyperGraphNodeFromNode(node)
		
		normalProcessNode(node)

		for _, functionNode in pairs(node.metrics.functionDefinitions) do
			local calleevalues = getCallerCalee(node, functionNode.name) 
			for _, value in pairs(calleevalues) do
				--[[
				print ('-----------')
				print ('Call node', value[1].tag, value[1].nodeid, value[1].text)
				print ('Caller function', value[2].tag, value[2].nodeid,  value[2].name)
				print ('Callee function', value[3].tag, value[3].nodeid,  value[3].name)
				print ('-----------')
				]]--
					
				if value[1] ~= nil and value[2] ~= nil and value[3] ~=nil then
					
					local callnode = getHyperGraphNodeFromNode(value[1])
					callnode.shortname = value[1].text

					local caller = getHyperGraphNodeFromNode(value[2])
					caller.shortname = value[2].name

					local callee = getHyperGraphNodeFromNode(value[3])
					callee.shortname = value[3].name

					local edge = HG.E'executes'
					edge.type = 'function'
					graph[edge] = { [HG.I'executor'] = caller, [HG.I'function'] = callee, [HG.I'executepoint'] = callnode }
						
				end
			end
		end

		node.hypergraph = graph

		graph:CreateNodes()

		return node
	end

	new_table['GlobalFunction'] = function(data) processFunction(data) normalProcessNode(data) return data end
	new_table['LocalFunction'] = function(data) processFunction(data) normalProcessNode(data) return data end
	new_table['Function'] = function(data) processFunction(data) normalProcessNode(data) return data end
	
	return new_table
end)()

