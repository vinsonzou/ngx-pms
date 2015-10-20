--[[
author: jie123108@163.com
date: 20151019
]]

local template = require "resty.template"
local config = require("config")
local userdao = require('dao.user_dao')
local permdao = require('dao.perm_dao')
local mysql = require("dao.mysql_util")
local json = require("util.json")
local dwz = require("Manager.lua.dwzutil")
local util = require("util.util")
local error = require('dao.error')
local tmpl_caching = config.tmpl_caching
if tmpl_caching == nil then
	tmpl_caching = false
end

local _M = {}

function _M.list_render()
	local errmsg = nil
	local totals = 0
	ngx.req.read_body()
    local args, err = ngx.req.get_post_args()
    if args.username == "" then
        args.username = nil
    end
    if args.email == "" then
        args.email = nil
    end
    if args.tel == "" then
        args.tel = nil
    end

	local dao = userdao:new()
	local pageNum = tonumber(args.pageNum) or 1
	local numPerPage = tonumber(args.numPerPage) or config.defNumPerPage
	local ok, users = dao:list(args, pageNum, numPerPage)
	if not ok then
		if users == error.err_data_not_exist then
			totals = 0
			users = {}
		else
			errmsg = users
			users = nil
		end
	else 
		ok, totals = dao:count(args)
		if not ok then
			totals = 0
		end
	end
	
	template.caching(tmpl_caching)
	template.render("user_list.html", {errmsg=errmsg, users=users, 
                    username=args.username, email=args.email, tel=args.tel,
                    pageNum=pageNum, numPerPage=numPerPage, totals=totals})
	ngx.exit(0)
end

function _M.add_render()
	ngx.req.read_body()
    local args, err = ngx.req.get_post_args()
	local id = tonumber(args.id)
	local dao = permdao:new()
    local perm_ok, permissions = dao:list(app)

	template.caching(tmpl_caching)
	template.render("user_add.html", {app=app,appname=appname,remark=remark})
	ngx.exit(0)
end

function _M.detail_render()
    local method_name = ngx.req.get_method()
    local args, err = nil
    if method_name == "POST" then
        ngx.req.read_body()
        args, err = ngx.req.get_post_args()
    else
        args = ngx.req.get_uri_args()
    end
    local id = tonumber(args.id)
    if not id then
        ngx.log(ngx.ERR, "args [id] missing!")
        ngx.say(dwz.cons_resp(300, "缺少必要的参数"))
        ngx.exit(0)
    end

    local dao = userdao:new()
    local ok, userinfo = dao:get_by_id(id)    

    if ok then
        --ngx.log(ngx.INFO, "---[", json.dumps(userinfo), "]---")
        template.caching(tmpl_caching)
        template.render("user_detail.html", {userinfo=userinfo})
        ngx.exit(0)
    else
        ngx.log(ngx.ERR, "dao:get_by_id(", tostring(id), ") failed err:", tostring(userinfo))
        ngx.say(dwz.cons_resp(300, "系统错误，查询用户信息时出错！"))
        ngx.exit(0)
    end

end

--[[
function _M.add_post()
	ngx.req.read_body()
    local args, err = ngx.req.get_post_args()

    local app = args.app 
    local appname = args.appname
    local remark = args.remark
    local create_time = ngx.time()
    local update_time = ngx.time()
    local appinfo = {app=app,appname=appname,remark=remark, 
    				create_time=create_time,update_time=update_time}

    local username = args.username
    local email = args.email
    local tel = args.tel 
    local password = util.random_pwd(16)
    local manager = args.manager 

    local userinfo = {username=username, email=email, tel=tel,password=password,
    					app=app,manager=manager,role_id="",permission="",
    					create_time=create_time,update_time=update_time}
    local ok, connection = mysql.connection_get()
    if not ok then
    	ngx.log(ngx.ERR, "mysql.connection_get failed! err:", tostring(connection))
    	ngx.say(dwz.cons_resp(300, "获取数据库链接出错了:" .. tostring(connection)))
    	ngx.exit(0)
    end

    -- 检查应用是否存在。
    local dao = userdao:new()
    local ok, exist = dao:exist("app", app)
    if ok and exist then
        mysql.connection_put(connection)
        ngx.say(dwz.cons_resp(300, "保存应用信息时出错了, 应用ID[" .. app .. "]已经存在!"))
        ngx.exit(0)
    end
    local ok, exist = dao:exist("appname", appname)
    if ok and exist then
        mysql.connection_put(connection)
        ngx.say(dwz.cons_resp(300, "保存应用信息时出错了, 应用名称[" .. appname .. "]已经存在!"))
        ngx.exit(0)
    end
    -- 检查用户是否存在
    local dao = userdao:new()
    local ok, exist = dao:exist("username", username)
    if ok and exist then
        mysql.connection_put(connection)
        ngx.say(dwz.cons_resp(300, "保存应用信息时出错了, 用户名[" .. username .. "]已经存在!"))
        ngx.exit(0)
    end
    local ok, exist = dao:exist("email", email)
    if ok and exist then
        mysql.connection_put(connection)
        ngx.say(dwz.cons_resp(300, "保存应用信息时出错了, EMAIL[" .. email .. "]已经存在!"))
        ngx.exit(0)
    end
    local ok, exist = dao:exist("tel", tel)
    if ok and exist then
        mysql.connection_put(connection)
        ngx.say(dwz.cons_resp(300, "保存应用信息时出错了, TEL[" .. tel .. "]已经存在!"))
        ngx.exit(0)
    end

    local tx_ok, tx_err = mysql.tx_begin(connection)
    if not tx_ok then
    	ngx.log(ngx.ERR, "mysql.tx_begin failed! err:", tostring(tx_err))
    end

    local dao = userdao:new(connection)
    local ok, err = dao:save(appinfo)
    if not ok then
    	ngx.log(ngx.ERR, "userdao:save(", json.dumps(appinfo, ") failed! err:", tostring(err)))
    	if tx_ok then 
    		tx_ok, tx_err = mysql.tx_rollback(connection)
    	end
        if err == error.err_data_exist then
            ngx.say(dwz.cons_resp(300, "保存应用信息时出错了: 数据重复"))
        else
    	   ngx.say(dwz.cons_resp(300, "保存应用信息时出错了:" .. tostring(err)))
        end
    	mysql.connection_put(connection)
    	ngx.exit(0)
    end
    local dao = userdao:new(connection)
    local ok, err = dao:save(userinfo)
    if not ok then
    	ngx.log(ngx.ERR, "userdao:save(", json.dumps(userinfo, ") failed! err:", tostring(err)))
    	if tx_ok then 
    		tx_ok, tx_err = mysql.tx_rollback(connection)
    	end
    	if err == error.err_data_exist then
            ngx.say(dwz.cons_resp(300, "保存应用信息时出错了: 数据重复"))
        else
           ngx.say(dwz.cons_resp(300, "保存应用管理员信息时出错了:" .. tostring(err)))
        end
    	mysql.connection_put(connection)
    	ngx.exit(0)
    end
    tx_ok, tx_err = mysql.tx_commit(connection)
    mysql.connection_put(connection)
    --TODO: 密码提示框会小时问题修改。
	ngx.say(dwz.cons_resp(200, "应用【" .. app .. "】添加成功，管理员：\n用户名：" 
					.. username .. "\n密码：" .. password, {navTabId="app_list"}))
end
]]

return _M