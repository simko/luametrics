
local pairs, print, table= pairs, print, table

local utils = require 'metrics.utils'
local HG = require 'hypergraph'
local keys = (require 'metrics.rules').rules

module ('metrics.captures.hypergraph')

graph = HG.H{}

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
	for _, child in pairs(data.data or {}) do
		graph[HG.E'treerelation'] = { [HG.I'parent'] = currentHyperNode, [HG.I'child'] = getHyperGraphNodeFromNode(child) }
	end

	return data 
end

function processFunction(funcAst)
	local funcHyperNode = getHyperGraphNodeFromNode(funcAst);
	
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
	
	local edge = HG.E'measures'
	local metric_i = HG.I'metric'
	edge.type = 'loc'
	edge.description = 'lines of code metric'
	metric_i.type = 'loc'
	metric_i.description = 'lines of code metric'
	graph[edge] = { [HG.I'subject'] = funcHyperNode, [metric_i] = getHyperGraphNodeFromNode(funcAst.metrics.LOC) }
	
end

captures = (function()
	local key,value
	local new_table = {}
	for key,value in pairs(keys) do
		new_table[key] = normalProcessNode
	end
	
	new_table[1] = function (node) 

		normalProcessNode(node)

		for _, functionNode in pairs(node.metrics.functionDefinitions) do
			if functionNode.name then 
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

						graph[HG.E'calls'] = { [HG.I'caller'] = caller, [HG.I'callee'] = callee, [HG.I'callnode'] = callnode }
						
					end
				end

			end
		end

		for _, functionNode in pairs(node.metrics.functionDefinitions) do
			
			if functionNode.name then 
				local functionHyperNode = getHyperGraphNodeFromNode(functionNode)				
				local block = utils.getBlockFromFunction(functionNode)
	
				if (block) then -- should always be true but to be sure
					
					for _ , variable in pairs(block.metrics.blockdata.locals_total) do
							local edge = HG.E'uses'
							edge.type = 'local_variable'
							edge.description = 'uses a local variable for block'
							graph[edge] = { [HG.I'user'] = functionHyperNode, [HG.I'local_variable'] = getHyperGraphNodeFromNode(variable[2][1]) }
							for _ , occurence in pairs(variable[2]) do
								graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
							end
					end
					
					for name, occurences in pairs(block.metrics.blockdata.remotes) do
						local edge = HG.E'uses'
						edge.type = 'remote_variable'
						edge.description = 'uses a remote variable for block'
						graph[edge] = { [HG.I'user'] = functionHyperNode, [HG.I'remote_variable'] = getHyperGraphNodeFromNode(utils.getVariableCommonPoint(occurences[1],name)) }
						for _ , occurence in pairs(occurences) do
							graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
						end
					end
					
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

