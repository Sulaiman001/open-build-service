require File.dirname(__FILE__) + '/../test_helper'
require 'source_controller'

class MaintenanceTests < ActionController::IntegrationTest 
  fixtures :all
  
  def test_branch_package
    ActionController::IntegrationTest::reset_auth 
    prepare_request_with_user "tom", "thunder"

    # branch a package which does not exist in update project via project link
    post "/source/BaseDistro/pack1", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro:Update/pack1/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "BaseDistro:Update"
    assert_equal ret.package, "pack1"
    assert_not_nil ret.baserev
    assert_not_nil ret.patches
    assert_not_nil ret.patches.branch

    # branch a package which does exist in update project
    post "/source/BaseDistro/pack2", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro:Update/pack2/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "BaseDistro:Update"
    assert_equal ret.package, "pack2"
    assert_not_nil ret.baserev
    assert_not_nil ret.patches
    assert_not_nil ret.patches.branch

    # branch a package which does not exist in update project, but update project is linked
    post "/source/BaseDistro2/pack2", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro2:LinkedUpdateProject/pack2/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "BaseDistro2:LinkedUpdateProject"
    assert_equal ret.package, "pack2"

    # check if we can upload a link to a packge only exist via project link
    put "/source/home:tom:branches:BaseDistro2:LinkedUpdateProject/pack2/_link", @response.body
    assert_response :success
  end

  def test_mbranch_and_maintenance_request
    prepare_request_with_user "king", "sunflower"
    put "/source/ServicePack/_meta", "<project name='ServicePack'><title/><description/><link project='kde4'/></project>"
    assert_response :success

    # setup maintained attributes
    prepare_request_with_user "maintenance_coord", "power"
    # an entire project
    post "/source/BaseDistro/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    # single packages
    post "/source/BaseDistro2/pack2/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/BaseDistro3/pack2/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/ServicePack/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success

    # search for maintained packages like osc is doing
    get "/search/package?match=%28%40name+%3D+%27pack2%27%29+and+%28project%2Fattribute%2F%40name%3D%27OBS%3AMaintained%27+or+attribute%2F%40name%3D%27OBS%3AMaintained%27%29"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.package.each.count, 3
   
    # do the real mbranch for default maintained packages
    ActionController::IntegrationTest::reset_auth 
    prepare_request_with_user "tom", "thunder"
    post "/source", :cmd => "branch", :package => "pack2"
    assert_response :success

    # validate result
    get "/source/home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2/_meta"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro/_meta"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2/_link"
    assert_response :success

    assert_tag :tag => "link", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :package => "pack2" }
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "BaseDistro:Update", :package => "pack2" }
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro3/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "BaseDistro3", :package => "pack2" }

    # test branching another package set into same project
    post "/source", :cmd => "branch", :package => "pack1", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack1.BaseDistro"
    assert_response :success

    # test branching another package set into same project from same project
    post "/source", :cmd => "branch", :package => "pack3", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack3.BaseDistro"
    assert_response :success
    # test branching another package only reachable via project link into same project
    post "/source", :cmd => "branch", :package => "kdelibs", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/kdelibs.ServicePack"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/kdelibs.ServicePack/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "ServicePack", :package => "kdelibs" }

    # validate created project meta
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    assert_response :success
    assert_tag :parent => { :tag => "build" }, :tag => "disable"

    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro2_BaseDistro2LinkedUpdateProject_repo" } }, 
               :tag => "path", :attributes => { :repository => "BaseDistro2LinkedUpdateProject_repo", :project => "BaseDistro2:LinkedUpdateProject" }
    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro2_BaseDistro2LinkedUpdateProject_repo" } }, 
               :tag => "arch", :content => "i586"

    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro_BaseDistroUpdateProject_repo" } }, 
               :tag => "path", :attributes => { :repository => "BaseDistroUpdateProject_repo", :project => "BaseDistro:Update" }

    # validate created package meta
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2/_meta"
    assert_response :success
    assert_tag :tag => "package", :attributes => { :name => "pack2.BaseDistro2", :project => "home:tom:branches:OBS_Maintained:pack2" }
    assert_tag :parent => { :tag => "build" }, :tag => "enable", :attributes => { :repository => "BaseDistro2_BaseDistro2LinkedUpdateProject_repo" }

    # and branch same package again and expect error
    post "/source", :cmd => "branch", :package => "pack1", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "double_branch_package" }
    assert_match(/branch target package already exists:/, @response.body)

    # create patchinfo
    post "/source/BaseDistro?cmd=createpatchinfo"
    assert_response 403
    post "/source/home:tom:branches:OBS_Maintained:pack2?cmd=createpatchinfo"
    assert_response 400
    assert_match(/No binary packages were found in project repositories/, @response.body)
    # FIXME: test with binaries
    post "/source/home:tom:branches:OBS_Maintained:pack2?cmd=createpatchinfo&force=1"
    assert_response :success

    # create maintenance request
    # without specifing target, the default target must get found via attribute
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_tag( :tag => "target", :attributes => { :project => "My:Maintenance" } )
    node = ActiveXML::XMLNode.new(@response.body)
    assert_equal node.has_attribute?(:id), true
    id = node.data['id']

    # accept request
    prepare_request_with_user "maintenance_coord", "power"
    post "/request/#{id}?cmd=changestate&newstate=accepted"
    assert_response :success

    get "/request/#{id}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    maintenanceProject=data.elements["/request/action/target"].attributes.get_attribute("project").to_s
    assert_not_equal maintenanceProject, "My:Maintenance"
    assert_match(/^My:Maintenance:#{Time.now.utc.year}-1/, maintenanceProject)

    # validate created project
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    oprojectmeta = ActiveXML::XMLNode.new(@response.body)
    assert_response :success
    get "/source/My:Maintenance:#{Time.now.utc.year}-1/_meta"
    assert_response :success
    assert_tag( :parent => {:tag => "build"}, :tag => "disable", :content => nil )
    node = ActiveXML::XMLNode.new(@response.body)
    assert_not_nil node.repository.data
    assert_equal node.repository.data, oprojectmeta.repository.data
    assert_equal node.build.data, oprojectmeta.build.data

    get "/source/My:Maintenance:#{Time.now.utc.year}-1"
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :count => "7" } )

    get "/source/My:Maintenance:#{Time.now.utc.year}-1/pack2.BaseDistro2/_meta"
    assert_response :success
    assert_tag( :tag => "enable", :parent => {:tag => "build"}, :attributes => { :repository => "BaseDistro2_BaseDistro2LinkedUpdateProject_repo" } )
  end

  def test_create_maintenance_project_and_release_packages
    prepare_request_with_user "maintenance_coord", "power"

    # setup a maintained distro
    post "/source/BaseDistro2/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/BaseDistro2/_attribute", "<attributes><attribute namespace='OBS' name='UpdateProject' > <value>BaseDistro2:LinkedUpdateProject</value> </attribute> </attributes>"
    assert_response :success
    post "/source/BaseDistro3/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success

    # create a maintenance incident
    post "/source", :cmd => "createmaintenanceincident"
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetproject" } )
    data = REXML::Document.new(@response.body)
    maintenanceProject=data.elements["/status/data"].text
    maintenanceID=maintenanceProject.gsub( /^My:Maintenance:/, "" )

    # submit packages via mbranch
    post "/source", :cmd => "branch", :package => "pack2", :target_project => maintenanceProject
    assert_response :success
    # correct branched ?
    get "/source/"+maintenanceProject+"/pack2.BaseDistro2/_link"
    assert_response :success
    assert_tag( :tag => "link", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :package => "pack2" } )
    get "/source/"+maintenanceProject+"/_meta"
    assert_response :success
    assert_tag( :tag => "path", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :repository => "BaseDistro2LinkedUpdateProject_repo" } )

    # FIXME: test with binaries
    post "/source/#{maintenanceProject}?cmd=createpatchinfo&force=1"
    assert_response :success
    get "/source/#{maintenanceProject}/_patchinfo/_patchinfo"
    assert_response :success
    assert_tag( :tag => "patchinfo", :attributes => { :incident => maintenanceID } )

    # create release request
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_release">
                                     <source project="' + maintenanceProject + '" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_no_tag( :tag => "target", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :package => "pack2" } )
    assert_no_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "pack2" } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :package => "pack2." + maintenanceID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "pack2." + maintenanceID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro2:LinkedUpdateProject", :package => "_patchinfo." + maintenanceID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "_patchinfo." + maintenanceID } )
    node = ActiveXML::XMLNode.new(@response.body)
    assert_equal node.has_attribute?(:id), true
    id = node.data['id']

    # FIXME2.3: not yet working
    return unless $ENABLE_BROKEN

    ### the backend is now building the packages, injecting results
    perlopts="-I#{RAILS_ROOT}/../backend -I#{RAILS_ROOT}/../backend/build"
    # run scheduler once to create job file
    IO.popen("cd #{RAILS_ROOT}/tmp/backend_config; exec perl #{perlopts} ./bs_sched --testmode i586") do |io|
       # just for waiting until scheduler finishes
       io.each {|line| line.strip unless line.blank? }
    end
    # find out about the triggered build job and write back dispatching data
    findMaintJob=IO.popen("find #{RAILS_ROOT}/tmp/backend_data/jobs/i586/ -name #{maintenanceProject}*")
    maintJob=findMaintJob.readlines.first.chomp
    jobid=""
    IO.popen("md5sum #{maintJob}|cut -d' ' -f 1") do |io|
       jobid = io.readlines.first.chomp
    end
    f = File.open("#{maintJob}:status", 'w')
    f.write( "<jobstatus code=\"building\"> <jobid>#{jobid}</jobid> </jobstatus>" )
    f.close
    # upload build result as a worker would do
    system("cd #{RAILS_ROOT}/test/fixtures/backend/binary/; exec find . -name '*i586.rpm' -o -name '*src.rpm' -o -name meta -o -name logfile | cpio -H newc -o | curl -s -X POST -T - 'http://localhost:3201/putjob?arch=i586&code=success&job=#{maintJob.gsub(/.*\//, '')}&jobid=#{jobid}'")
    # run scheduler again to collect result
    IO.popen("cd #{RAILS_ROOT}/tmp/backend_config; exec perl #{perlopts} ./bs_sched --testmode i586") do |io|
       # just for waiting until scheduler finishes
       io.each {|line| line.strip unless line.blank? }
    end

    # release packages
    prepare_request_with_user "king", "sunflower"
    post "/request/#{id}?cmd=changestate&newstate=accepted"
    assert_response :success

    # validate result
    get "/source/BaseDistro2:LinkedUpdateProject/pack2/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => nil, :package => "pack2.2011-1" }
    get "/source/BaseDistro2:LinkedUpdateProject/pack2.2011-1/_link"
    assert_response 404
  end

  def test_copy_project_for_release
    # as user
    prepare_request_with_user "tom", "thunder"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro"
    assert_response 403
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro"
    assert_response :success
    delete "/source/home:tom:CopyOfBaseDistro"
    assert_response :success

    # as admin
    prepare_request_with_user "king", "sunflower"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro"
    assert_response :success
    get "/source/CopyOfBaseDistro/_meta"
    assert_response :success
    get "/source/BaseDistro"
    assert_response :success
    opackages = ActiveXML::XMLNode.new(@response.body)
    get "/source/CopyOfBaseDistro"
    assert_response :success
    packages = ActiveXML::XMLNode.new(@response.body)
    assert_equal opackages.to_s, packages.to_s

    # compare revisions
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    history = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = history.each_revision.last.srcmd5.text
    version = history.each_revision.last.version.text
    time = history.each_revision.last.time.text
    vrev = history.each_revision.last.vrev
    assert_not_nil srcmd5
    get "/source/CopyOfBaseDistro/pack2/_history"
    assert_response :success
    copyhistory = ActiveXML::XMLNode.new(@response.body)
    copysrcmd5 = copyhistory.each_revision.last.srcmd5.text
    copyversion = copyhistory.each_revision.last.version.text
    copytime = copyhistory.each_revision.last.time.text
    copyrev = copyhistory.each_revision.last.rev
    copyvrev = copyhistory.each_revision.last.vrev
    assert_equal srcmd5, copysrcmd5
    assert_equal vrev.to_i, copyvrev.to_i - 1  #the copy gets always an additional commit
    assert_equal version, copyversion
    assert_not_equal time, copytime
    assert_equal copyhistory.each_revision.last.user.text, "king"

    delete "/source/CopyOfBaseDistro"
    assert_response :success
  end

  def test_copy_project_for_release_with_history_and_binaries
    prepare_request_with_user "tom", "thunder"
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withhistory=1"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "project_copy_no_permission" }
    prepare_request_with_user "tom", "thunder"
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withbinaries=1"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "project_copy_no_permission" }

    # as admin
    prepare_request_with_user "king", "sunflower"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withhistory=1&withbinaries=1"
    assert_response :success
    get "/source/CopyOfBaseDistro/_meta"
    assert_response :success
    get "/source/BaseDistro"
    assert_response :success
    opackages = ActiveXML::XMLNode.new(@response.body)
    get "/source/CopyOfBaseDistro"
    assert_response :success
    packages = ActiveXML::XMLNode.new(@response.body)
    assert_equal opackages.to_s, packages.to_s

    # compare revisions
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    history = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = history.each_revision.last.srcmd5.text
    version = history.each_revision.last.version.text
    time = history.each_revision.last.time.text
    vrev = history.each_revision.last.vrev
    assert_not_nil srcmd5
    get "/source/CopyOfBaseDistro/pack2/_history"
    assert_response :success
    copyhistory = ActiveXML::XMLNode.new(@response.body)
    copysrcmd5 = copyhistory.each_revision.last.srcmd5.text
    copyversion = copyhistory.each_revision.last.version.text
    copytime = copyhistory.each_revision.last.time.text
    copyrev = copyhistory.each_revision.last.rev
    copyvrev = copyhistory.each_revision.last.vrev
    assert_equal srcmd5, copysrcmd5
    assert_equal vrev.to_i, copyvrev.to_i - 1  #the copy gets always an additional commit
    assert_equal version, copyversion
    assert_not_equal time, copytime
    assert_equal copyhistory.each_revision.last.user.text, "king"

    # compare binaries
    get "/build/BaseDistro/BaseDistro_repo/i586/pack2"
    assert_response :success
    assert_tag :tag => "binary", :attributes => { :filename => "package-1.0-1.i586.rpm" }

    delete "/source/CopyOfBaseDistro"
    assert_response :success
  end

end
