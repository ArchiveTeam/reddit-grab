dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local posts = {}
local requested_children = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

processed = function(url)
  if downloaded[url] or addedtolist[url] then
    return true
  end
  return false
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?context=[0-9]+&depth=[0-9]+")
      or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?depth=[0-9]+&context=[0-9]+")
      or string.match(url, "^https?://[^/]*reddit%.com/login")
      or string.match(url, "^https?://[^/]*reddit%.com/register")
      or string.match(url, "%?sort=")
      or string.match(url, "^https?://[^/]*reddit%.app%.link/")
      or string.match(url, "^https?://out%.reddit%.com/r/")
      or (string.match(url, "^https?://gateway%.reddit%.com/") and not string.match(url, "/morecomments/"))
      or string.match(url, "/%.rss$")
      or (parenturl and string.match(url, "^https?://amp%.reddit%.com/")) then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if url .. "/" == parenturl then
    return false
  end

  if string.match(url, "^https?://[^/]*redditmedia%.com/")
      or string.match(url, "^https?://old%.reddit%.com/api/morechildren$")
      or string.match(url, "^https?://v%.redd%.it/[^/]+/[^/]+$")
      or string.match(url, "^https?://preview%.redd%.it/[^/]+/[^/]+$") then
    return true
  end

  for s in string.gmatch(url, "([a-z0-9]+)") do
    if posts[s] then
      return true
    end
  end

  if parenturl
      and string.match(parenturl, "^https?://www%.reddit%.com/")
      and not string.match(url, "^https?://[^/]*reddit%.com/")
      and not string.match(url, "^https?://[^/]*youtube%.com")
      and not string.match(url, "^https?://[^/]*youtu%.be")
      and not string.match(url, "^https?://[^/]*redd%.it/") then
    return true
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]") then
    return false
  end

  if not processed(url)
      and (allowed(url, parent["url"]) or (allowed(parent["url"]) and html == 0)) then
    addedtolist[url] = true
print('b ' .. html .. ' ' .. url)
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if not processed(url_)
        and allowed(url_, origurl)
        and not (string.match(url_, "[^/]$") and processed(url_ .. "/")) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
print('a ' .. url)
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if string.match(url, "^https?://www%.reddit%.com/comments/[a-z0-9]+$")
      or string.match(url, "^https?://old%.reddit%.com/comments/[a-z0-9]+$") then
    posts[string.match(url, "[a-z0-9]+$")] = true
  end

  if allowed(url, nil)
      and not string.match(url, "^https?://[^/]*redditmedia%.com/")
      and not string.match(url, "^https?://[^/]*redditstatic%.com/")
      and not string.match(url, "^https?://out%.reddit%.com/")
      and not string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]*%.ts$")
      and not string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]*$") then
    html = read_file(file)
    if string.match(url, "^https://old.reddit.com/api/morechildren$") then
      html = string.gsub(html, '\\"', '"')
    end
    if string.match(url, "^https?://old%.reddit%.com/") then
      for s in string.gmatch(html, "(return%s+morechildren%(this,%s*'[^']+',%s*'[^']+',%s*'[^']+',%s*[0-9]+,%s*'[^']+'%))") do
        local link_id, sort, children, depth, limit_children = string.match(s, "%(this,%s*'([^']+)',%s*'([^']+)',%s*'([^']+)',%s*([0-9]+),%s*'([^']+)'%)$")
        local id = string.match(children, "^([^,]+)")
        local subreddit = string.match(html, 'data%-subreddit="([^"]+)"')
        local post_data = "link_id=" .. link_id .. "&sort=" .. sort .. "&children=" .. string.gsub(children, ",", "%%2C") .. "&depth=" .. depth .. "&id=t1_" .. id .. "&limit_children=" .. limit_children .. "&r=" .. subreddit .. "&renderstyle=html"
        if requested_children[post_data] == nil then
          requested_children[post_data] = true
          table.insert(urls, {url="https://old.reddit.com/api/morechildren",
                              post_data=post_data})
        end
      end
    elseif string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/[^/]")
        or string.match(url, "^https?://www%.reddit%.com/comments/[^/]")
        or string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_[^%?]") then
      for s in string.gmatch(html, '"token"%s*:%s*"([^"]+)"') do
        local post_data = '{"token":"' .. s .. '"}'
        local comment_id = nil
        if string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/[^/]") then
          comment_id = string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/([^/]+)")
        elseif string.match(url, "^https?://www%.reddit%.com/comments/[^/]") then
          comment_id = string.match(url, "^https?://www%.reddit%.com/comments/([^/]+)")
        elseif string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_[^%?]") then
          comment_id = string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_([^%?]+)")
        end
        if requested_children[post_data] == nil then
          requested_children[post_data] = true
          table.insert(urls, {url="https://gateway.reddit.com/desktopapi/v1/morecomments/t3_" .. comment_id .. "?rtj=only&allow_over18=1&include=",
                              post_data=post_data})
        end
      end
    end
    if string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/") then
      for s in string.gmatch(html, '"permalink"%s*:%s*"([^"]+)"') do
        check("https?://www.reddit.com" .. s)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.mpd$") then
      for s in string.gmatch(html, "<BaseURL>([^<]+)</BaseURL>") do
        checknewshorturl(s)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.m3u8$") then
      for s in string.gmatch(html, "(.-)\n") do
        if not string.match(s, "^#") then
          checknewshorturl(s)
        end
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true then
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 8
    if not allowed(url["url"], nil) then
        maxtries = 0
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
