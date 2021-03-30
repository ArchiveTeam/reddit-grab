dofile("table_show.lua")
dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")
JSON = (loadfile "JSON.lua")()

local item_names = os.getenv('item_names')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')
local item_type = nil
local item_name = nil
local item_value = nil

local selftext = nil

local item_types = {}
for s in string.gmatch(item_names, "([^\n]+)") do
  local t, n = string.match(s, "^([^:]+):(.+)$")
  item_types[n] = t
end

if urlparse == nil or http == nil then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local posts = {}
local requested_children = {}
local thumbs = {}

local outlinks = {}

local bad_items = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

abort_item = function(item)
  abortgrab = true
  if not item then
    item = item_name
  end
  if not bad_items[item] then
    io.stdout:write("Aborting item " .. item .. ".\n")
    io.stdout:flush()
    bad_items[item] = true
  end
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
  local match = string.match(url, "^https?://[^%.]+%.thumbs%.redditmedia%.com/([^%.]+)%.")
  if match
    and parenturl
    and string.match(parenturl, "^https?://www%.reddit%.com/api/info%.json%?id=") then
    thumbs[match] = true
  end

  if match and not thumbs[match] then
    return false
  end

  if string.match(url, "'+")
    or string.match(urlparse.unescape(url), "[<>\\%$%^%[%]%(%){}]")
    or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?context=[0-9]+&depth=[0-9]+")
    or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?depth=[0-9]+&context=[0-9]+")
    or string.match(url, "^https?://[^/]*reddit%.com/login")
    or string.match(url, "^https?://[^/]*reddit%.com/register")
    or string.match(url, "%?sort=")
    or string.match(url, "%?limit=500$")
    or string.match(url, "%?ref=readnext$")
    or string.match(url, "^https?://v%.redd%.it/.+%?source=fallback$")
    or string.match(url, "^https?://[^/]*reddit%.app%.link/")
    or string.match(url, "^https?://out%.reddit%.com/r/")
    or string.match(url, "^https?://emoji%.redditmedia%.com/")
    or string.match(url, "^https?://styles%.redditmedia%.com/")
    or string.match(url, "^https?://old%.reddit%.com/gallery/")
    or string.match(url, "^https?://old%.reddit%.com/gold%?")
    or string.match(url, "^https?://[^%.]+%.redd%.it/award_images/")
    or string.match(url, "^https?://[^/]+/over18.+dest=https%%3A%%2F%%2Fold%.reddit%.com")
    or string.match(url, "^https?://old%.[^%?]+%?utm_source=reddit")
    or (
      string.match(url, "^https?://gateway%.reddit%.com/")
      and not string.match(url, "/morecomments/")
    )
    or string.match(url, "/%.rss$")
    or (
      parenturl
      and string.match(url, "^https?://amp%.reddit%.com/")
    )
    or (
      item_type == "post"
      and (
        string.match(url, "^https?://[^/]*reddit%.com/r/[^/]+/comments/[0-9a-z]+/[^/]+/[0-9a-z]+/?$")
        or string.match(url, "^https?://[^/]*reddit%.com/r/[^/]+/comments/[0-9a-z]+/[^/]+/[0-9a-z]+/?%?utm_source=")
      )
    )
    or (
      parenturl
      and string.match(parenturl, "^https?://[^/]*reddit%.com/r/[^/]+/duplicates/")
      and string.match(url, "^https?://[^/]*reddit%.com/r/[^/]+/duplicates/")
    )
    or (
      parenturl
      and string.match(parenturl, "^https?://[^/]*reddit%.com/user/[^/]+/duplicates/")
      and string.match(url, "^https?://[^/]*reddit%.com/user/[^/]+/duplicates/")
    ) then
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

  if not (
    string.match(url, "^https?://[^/]*redd%.it/")
    or string.match(url, "^https?://[^/]*reddit%.com/")
    or string.match(url, "^https?://[^/]*redditmedia%.com/")
  ) then
    if not string.match(url, "^https?://[^/]*redditstatic%.com/") then
      outlinks[url] = true
    end
    return false
  end

  if url .. "/" == parenturl then
    return false
  end

  if string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/")
    or string.match(url, "^https?://old%.reddit%.com/api/morechildren$") then
    return true
  end

  if (string.match(url, "^https?://[^/]*redditmedia%.com/")
      or string.match(url, "^https?://v%.redd%.it/")
      or string.match(url, "^https?://i%.redd%.it/")
      or string.match(url, "^https?://[^%.]*preview%.redd%.it/.")
    )
    and not string.match(item_type, "comment") then
    if parenturl
      and string.match(parenturl, "^https?://www%.reddit.com/api/info%.json%?id=t")
      and not string.match(url, "^https?://v%.redd%.it/")
      and not string.find(url, "thumbs.") then
      return false
    end
    return true
  end

  for s in string.gmatch(url, "([a-z0-9]+)") do
    if posts[s] then
      return true
    end
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if item_type == "comment" then
    return false
  end

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "^https?://[^/]*redditstatic%.com/")
    or string.match(url, "^https?://old%.reddit%.com/static/")
    or string.match(url, "^https?://www%.reddit%.com/static/")
    or string.match(url, "^https?://styles%.redditmedia%.com/")
    or string.match(url, "^https?://emoji%.redditmedia%.com/")
    or string.match(url, "/%.rss$") then
    return false
  end

  if string.match(parent["url"], "^https?://old%.reddit%.com/comments/[a-z0-9]+") then
    return true
  end

  url = string.gsub(url, "&amp;", "&")

  if not processed(url)
    and (allowed(url, parent["url"]) or (allowed(parent["url"]) and html == 0)) then
    addedtolist[url] = true
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
    local url_ = string.match(url, "^(.-)%.?$")
    while string.find(url_, "&amp;") do
      url_ = string.gsub(url_, "&amp;", "&")
    end
    if not processed(url_)
        and string.match(url_, "^https?://.+")
        and allowed(url_, origurl)
        and not (string.match(url_, "[^/]$") and processed(url_ .. "/")) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
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
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (
      string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^data:")
      or string.match(newurl, "^irc:")
      or string.match(newurl, "^%${")
    ) then
      check(urlparse.absolute(url, newurl))
    end
  end

  if string.match(url, "^https?://www%.reddit%.com/")
    and not string.match(url, "/api/") then
    check(string.gsub(url, "^https?://www%.reddit%.com/", "https://old.reddit.com/"))
  end

  local match = string.match(url, "^https?://preview%.redd%.it/([a-zA-Z0-9]+%.[a-zA-Z0-9]+)")
  if match then
    check("https://i.redd.it/" .. match)
  end

  if allowed(url)
    and status_code < 300
    and not string.match(url, "^https?://[^/]*redditmedia%.com/")
    and not string.match(url, "^https?://[^/]*redditstatic%.com/")
    and not string.match(url, "^https?://out%.reddit%.com/")
    and not string.match(url, "^https?://[^%.]*preview%.redd%.it/")
    and not string.match(url, "^https?://i%.redd%.it/")
    and not (
      string.match(url, "^https?://v%.redd%.it/")
      and not string.match(url, "%.m3u8")
      and not string.match(url, "%.mpd")
    ) then
    html = read_file(file)
    if string.match(url, "^https?://www%.reddit%.com/[^/]+/[^/]+/comments/[0-9a-z]+/[^/]+/[0-9a-z]*/?$") then
      check(url .. "?utm_source=reddit&utm_medium=web2x&context=3")
    end
    if string.match(url, "^https?://old%.reddit%.com/api/morechildren$") then
      html = string.gsub(html, '\\"', '"')
    elseif string.match(url, "^https?://old%.reddit%.com/r/[^/]+/comments/")
      or string.match(url, "^https?://old%.reddit%.com/r/[^/]+/duplicates/") then
      html = string.gsub(html, "<div%s+class='spacer'>%s*<div%s+class=\"titlebox\">.-</div>%s*</div>%s*<div%s+class='spacer'>%s*<div%s+id=\"ad_[0-9]+\"%s*class=\"ad%-container%s*\">", "")
    end    
    if string.match(url, "^https?://old%.reddit%.com/") then
      for s in string.gmatch(html, "(return%s+morechildren%(this,%s*'[^']+',%s*'[^']+',%s*'[^']+',%s*'[^']+'%))") do
        local link_id, sort, children, limit_children = string.match(s, "%(this,%s*'([^']+)',%s*'([^']+)',%s*'([^']+)',%s*'([^']+)'%)$")
        local id = string.match(children, "^([^,]+)")
        local subreddit = string.match(html, 'data%-subreddit="([^"]+)"')
        local post_data = 
          "link_id=" .. link_id ..
          "&sort=" .. sort ..
          "&children=" .. string.gsub(children, ",", "%%2C") ..
          "&id=t1_" .. id ..
          "&limit_children=" .. limit_children ..
          "&r=" .. subreddit ..
          "&renderstyle=html"
        if not requested_children[post_data] then
          requested_children[post_data] = true
          table.insert(urls, {url="https://old.reddit.com/api/morechildren",
                              post_data=post_data})
        end
      end
    elseif string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/[^/]")
      or string.match(url, "^https?://www%.reddit%.com/user/[^/]+/comments/[^/]")
      or string.match(url, "^https?://www%.reddit%.com/comments/[^/]")
      or string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_[^%?]") then
      local comments_data = nil
      if string.match(url, "^https?://www%.reddit%.com/") then
        comments_data = string.match(html, '<script%s+id="data">%s*window%.___r%s*=%s*({.+});%s*</script>%s*<script>')
        if comments_data == nil then
          print("Could not find comments data.")
          abort_item()
        end
        comments_data = load_json_file(comments_data)["moreComments"]["models"]
      elseif string.match(url, "^https?://gateway%.reddit%.com/") then
        comments_data = load_json_file(html)["moreComments"]
      end
      if comments_data == nil then
        print("Error handling comments data.")
        abort_item()
      end
      local comment_id = string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/([^/]+)")
      if comment_id == nil then
        comment_id = string.match(url, "^https?://www%.reddit%.com/user/[^/]+/comments/([^/]+)")
      end
      if comment_id == nil then
        comment_id = string.match(url, "^https?://www%.reddit%.com/comments/([^/]+)")
      end
      if comment_id == nil then
        comment_id = string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_([^%?]+)")
      end
      if comment_id == nil then
        print("Could not find comment ID.")
        abort_item()
      end
      for _, d in pairs(comments_data) do
        if d["token"] == nil then
          print("Could not find token.")
          abort_item()
        end
        local post_data = '{"token":"' .. d["token"] .. '"}'
        if not requested_children[post_data] then
          requested_children[post_data] = true
          table.insert(urls, {url=
            "https://gateway.reddit.com/desktopapi/v1/morecomments/t3_" .. comment_id .. 
            "?emotes_as_images=true" ..
            "&rtj=only" ..
            "&allow_over18=1" ..
            "&include=",
            post_data=post_data
          })
        end
      end
    end
    if string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/") then
      for s in string.gmatch(html, '"permalink"%s*:%s*"([^"]+)"') do
        check("https?://www.reddit.com" .. s)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.mpd") then
      local max_size = 0
      local max_size_url = nil
      for s in string.gmatch(html, "<BaseURL>([^<]+)</BaseURL>") do
        local size = string.match(s, "([0-9]+)%.mp4")
        if size then
          size = tonumber(size)
          if size > max_size then
            max_size = size
            max_size_url = s
          end
        else
          checknewshorturl(s)
        end
      end
      if max_size_url then
        checknewshorturl(max_size_url)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.m3u8") then
      local bandwidth = 0
      local url = nil
      local has_uri = nil
      for s in string.gmatch(html, "(.-)\n") do
        if string.match(s, "^#") then
          local uri = string.match(s, 'URI="([^"]+)"')
          if (uri and not has_uri) or (not uri and has_uri) then
            if url then
              checknewshorturl(url)
            end
            bandwidth = 0
            url = nil
          end
          local n = string.match(s, "BANDWIDTH=([0-9]+)")
          if n then
            n = tonumber(n)
          end
          if uri then
            has_uri = true
            if n then
              if n > bandwidth then
                bandwidth = n
                url = uri
              end
            else
              checknewshorturl(uri)
            end
          elseif n then
            has_uri = false
            if n > bandwidth then
              bandwidth = n
              url = nil
            end
          end
        elseif not string.find(s, ".m3u8") then
          checknewshorturl(s)
        else
          if not has_uri and not url then
            url = s
          end
        end
      end
      if url then
        checknewshorturl(url)
      end
    end
    if string.match(url, "^https?://www%.reddit.com/api/info%.json%?id=t") then
      json = load_json_file(html)
      if not json or not json["data"] or not json["data"]["children"] then
        io.stdout:write("Could not load JSON.\n")
        io.stdout:flush()
        abort_item()
      end
      for _, child in pairs(json["data"]["children"]) do
        if not child["data"] or not child["data"]["permalink"] then
          io.stdout:write("Permalink is missing.\n")
          io.stdout:flush()
          abort_item()
        end
        if selftext then
          io.stdout:write("selftext already found.\n")
          io.stdout:flush()
          abort_item()
        end
        selftext = child["data"]["selftext"]
        checknewurl(child["data"]["permalink"])
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
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. " \n")
  io.stdout:flush()

  local match = string.match(url["url"], "^https?://www%.reddit.com/api/info%.json%?id=t[0-9]_([a-z0-9]+)$")
  if match then
    abortgrab = false
    selftext = nil
    posts[match] = true
    if not item_types[match] then
      io.stdout:write("Type for ID not found.\n")
      io.stdout:flush()
      abort_item()
    end
    item_type = item_types[match]
    item_value = match
    item_name = item_type .. ":" .. item_value
  end

  if status_code == 204 then
    return wget.actions.EXIT
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if string.match(newloc, "inactive%.min")
      or string.match(newloc, "ReturnUrl")
      or string.match(newloc, "adultcontent") then
      io.stdout:write("Found invalid redirect.\n")
      io.stdout:flush()
      abort_item()
    end
    if processed(newloc) or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab then
    abort_item()
    return wget.actions.EXIT
  end

  if status_code == 403 and string.match(url["url"], "^https?://v%.redd%.it/")
    and selftext == "[deleted]" then
    return wget.actions.EXIT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 8
    if not allowed(url["url"]) then
        maxtries = 0
    end
    if tries >= maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"]) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    end
    os.execute("sleep " .. math.floor(math.pow(2, tries)))
    tries = tries + 1
    return wget.actions.CONTINUE
  end

  if string.match(url["url"], "^https?://[^/]+%.reddit%.com/api/info%?id=t[0-9]_[a-z0-9]+$") then
    return wget.actions.EXIT
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir .. '/' .. warc_file_base .. '_bad-items.txt', 'w')
  for url, _ in pairs(bad_items) do
    file:write(url .. "\n")
  end
  file:close()
  local items = nil
  for item, _ in pairs(outlinks) do
    print('found item', item)
    if items == nil then
      items = item
    else
      items = items .. "\0" .. item
    end
  end
  if items ~= nil then
    local tries = 0
    while tries < 10 do
      local body, code, headers, status = http.request(
        "http://blackbird-amqp.meo.ws:23038/urls-t05crln9brluand/",
        items
      )
      if code == 200 or code == 409 then
        break
      end
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
    end
    if tries == 10 then
      abort_item()
    end
  end
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab then
    abort_item()
  end
  return exit_status
end
