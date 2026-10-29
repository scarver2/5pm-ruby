module FivePM
  class Authentication < Service
    def authorized_user
      call("getAuthorizedUser")
    end

    def ssl?
      call("isSsl")
    end
  end

  class Users < Resource
    def find_by_email(email)
      call("getByEmail", email: email)
    end
  end

  class Activity < Resource
    def files(filter: nil, offset: nil, count: nil)
      call("getFilesList", filter: filter, offset: offset, count: count)
    end

    # Preserve the WSDL FileList representation; never infer content encoding or
    # follow URLs returned inside records. Actual attachment behavior needs a tenant.
    def attach_files(activity_id:, files:)
      files = files.to_h if files.is_a?(Models::Record)
      raise ArgumentError, "files must be a FileList object" unless files.is_a?(Hash)

      call("attachFiles", activityId: activity_id, files: files)
    end

    def delete_file(id)
      call("removeFile", id: id)
    end

    def download_file(id)
      call("downloadFile", id: id, stream: false)
    end
  end
end
