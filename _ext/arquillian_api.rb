require 'rubygems'
require 'rexml/document'
require 'ostruct'
require 'json'
require 'git'


module Awestruct
  module Extensions
    module Arquillian
      module API

        class Containers
          def initialize(output_path = "/api/containers.json")
            @output_path = output_path
            @container_exp = /.*\-(managed|remote|embedded).*/
            @branch = 'master'
          end

          def execute(site)

            containers = []

            site.pages.each do |page|
              next unless page.git_repo

              repo = page.git_repo

              root_tree = repo.gtree @branch
              root_tree.children.each do |entry|
                next unless entry[0].eql? 'pom.xml'
                root_pom = REXML::Document.new(repo.object(entry[1]).contents)
                root_pom.elements.each 'project/modules/module' do |x|
                  if x.text =~ @container_exp

                    container = OpenStruct.new
                    containers << container

                    container_tree = repo.gtree "#{@branch}:#{x.text}"
                    container_tree.children.each do |sub_entry|
                      next unless sub_entry[0].eql? 'pom.xml'

                      container_pom = REXML::Document.new(repo.object(sub_entry[1]).contents)
                      container.name = container_pom.get_text 'project/name'
                      container.artifact_id = container_pom.get_text 'project/artifactId'

                      group_id = container_pom.get_text 'project/groupId'
                      group_id = root_pom.get_text 'project/groupId' unless group_id
                      container.group_id = group_id

                      container_pom.elements.each 'project/dependencies/dependency' do |dep|
                        next unless dep.get_text('scope').to_s.eql? 'provided'

                        container.dependencies = [] unless container.dependencies

                        dependency = OpenStruct.new
                        container.dependencies << dependency

                        dependency.group_id = dep.get_text 'groupId'
                        dependency.artifact_id = dep.get_text 'artifactId'

                      end

                      container_pom.elements.each 'project/build/plugins/plugin/artifactId[text()="maven-dependency-plugin"]' do |build|

                        build.elements.each '//artifactItem' do |download|

                          download_artifact = OpenStruct.new
                          download_artifact.group_id = download.get_text 'groupId'
                          download_artifact.artifact_id = download.get_text 'artifactId'

                          container.download = download_artifact
                        end
                      end

                      container_pom.elements.each 'project/build/plugins/plugin/artifactId[text()="maven-antrun-plugin"]' do |build|

                        build.elements.each '//get' do |download|

                          download_artifact = OpenStruct.new
                          download_artifact.url = download.attribute 'src'

                          container.download = download_artifact
                        end
                      end

                    end
                  end
                end
              end
            end

            if site.engine
              json_page = site.engine.load_page(
                File.join( File.dirname( __FILE__ ), 'arquillian_api_template.html.haml' ) )
              json_page.output_path = File.join( @output_path )

              json_page.arquillian_api_json = JSON.pretty_generate containers

              site.pages << json_page
            elsif
              # Used by the manual 'test' at the bottom
              puts JSON.pretty_generate containers
            end

          end
        end

      end
    end
  end
end

# Add to_json method to help JSON export OpenStruct objects
class OpenStruct
   def to_json a
     table.to_json a
   end
 end

def execute_arquillian_api_test
  repos = []
  repos << '_tmp/github/repo/arquillian-container-jbossas/'
  repos << '_tmp/github/repo/arquillian-container-tomcat/'
  repos << '_tmp/github/repo/arquillian-container-glassfish/'
  repos << '_tmp/github/repo/arquillian-container-jetty/'
  repos << '_tmp/github/repo/arquillian-container-was/'
  repos << '_tmp/github/repo/arquillian-container-openejb/'
  repos << '_tmp/github/repo/arquillian-container-openwebbeans/'

  site = OpenStruct.new
  site.pages = []

  repos.each do |repo|
    page = OpenStruct.new
    page.git_repo = Git.open repo

    site.pages << page
  end

  api = Awestruct::Extensions::Arquillian::API::Containers.new
  api.execute(site)
end

#execute_arquillian_api_test
