import sys
import shutil
import json
import os
import time
import requests
from loguru import logger
from urllib.parse import urlparse


def downloadIfUrl(url: str, temp_dir: str) -> str:
    """Download file from URL if it's a valid URL, otherwise return the original string"""
    try:
        # Check if it's a valid URL
        if not (url.startswith("http") or url.startswith("https") or url.startswith("ftp")):
            return url

        # Parse URL to get filename
        parsed_url = urlparse(url)
        filename = os.path.basename(parsed_url.path)

        # If no filename in URL, generate one based on content type
        if not filename or '.' not in filename:
            filename = "downloaded_file"

        # Create full path
        file_path = os.path.join(temp_dir, filename)

        # Download the file
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()

        # Determine extension from content type if not in filename
        if '.' not in filename:
            content_type = response.headers.get('content-type', '')
            if 'image/jpeg' in content_type:
                file_path += '.jpg'
            elif 'image/png' in content_type:
                file_path += '.png'
            elif 'image/gif' in content_type:
                file_path += '.gif'
            elif 'video/mp4' in content_type:
                file_path += '.mp4'
            elif 'audio/mpeg' in content_type:
                file_path += '.mp3'
            elif 'audio/wav' in content_type:
                file_path += '.wav'

        # Write file
        with open(file_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        # Check if file is empty
        if os.path.getsize(file_path) == 0:
            os.remove(file_path)
            raise Exception(f"Downloaded file is empty: {url}")

        return file_path

    except Exception as e:
        # If download fails, return original URL
        logger.warning(f"Failed to download {url}: {e}")
        return url

# Assuming BaseGenerator is in a module named 'generator'
# from generator import BaseGenerator


# Mock BaseGenerator if it's not available in the current context
class BaseGenerator:
    def __init__(self, task_data):
        self.task_data = task_data
        self.logger = logger


BASE_URL = "https://www.runninghub.cn"

DEBUG = False


class RunningHubClient:
    def __init__(self, api_key):
        self.api_key = api_key
        self.headers = {"Content-Type": "application/json"}

    def _post_with_retry(self, url, **kwargs):
        max_retries = 3
        for i in range(max_retries):
            try:
                # Set a default timeout if not provided
                if 'timeout' not in kwargs:
                    kwargs['timeout'] = 60

                response = requests.post(url, **kwargs)
                response.raise_for_status()
                return response
            except requests.exceptions.HTTPError as e:
                # Retry on 502 Bad Gateway and 504 Gateway Time-out
                if e.response.status_code in [502, 504]:
                    if i < max_retries - 1:
                        sleep_time = 2 * (i + 1)
                        logger.warning(f"Request failed with {e.response.status_code}, retrying in {sleep_time}s ({i+1}/{max_retries})...")
                        time.sleep(sleep_time)
                        continue
                raise e
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
                if i < max_retries - 1:
                    sleep_time = 2 * (i + 1)
                    logger.warning(f"Request connection failed: {e}, retrying in {sleep_time}s ({i+1}/{max_retries})...")
                    time.sleep(sleep_time)
                    continue
                raise e

    def upload_resource(self, file_path):
        logger.info(f"[上传资源] 输入: file_path={file_path}")
        url = "https://www.runninghub.cn/task/openapi/upload"
        data = {"apiKey": self.api_key, "fileType": "image"}
        with open(file_path, "rb") as f:
            files = {"file": (os.path.basename(file_path), f)}
            response = self._post_with_retry(url, data=data, files=files)
        result = response.json()
        logger.info(f"[上传资源] 输出: {result}")
        if result.get("code") != 0:
            raise Exception(f"上传资源失败: {result.get('msg')}")
        return result["data"]["fileName"]

    def start_task(self, workflow_id, node_info_list):
        logger.info(
            f"[启动任务] 输入: workflow_id={workflow_id}, node_info_list={json.dumps(node_info_list, indent=4, ensure_ascii=False)}"
        )
        url = f"{BASE_URL}/task/openapi/create"
        payload = {
            "apiKey": self.api_key,
            "workflowId": workflow_id,
            "nodeInfoList": node_info_list,
        }
        response = self._post_with_retry(url, json=payload)
        result = response.json()
        logger.info(f"[启动任务] 输出: {result}")
        if result.get("code") != 0:
            if result.get("code") == 810:
                raise Exception(
                    f"启动任务失败: 工作流 (workflowId: {workflow_id}) 未保存或未运行. 请在 RunningHub 平台上检查该工作流的状态。 ({result.get('msg')})"
                )
            raise Exception(f"启动任务失败: {result.get('msg')}")
        return result.get("data", {})

    def run_ai_app_task(self, webapp_id, node_info_list):
        logger.info(
            f"[发起AI应用任务] 输入: webapp_id={webapp_id}, node_info_list={json.dumps(node_info_list, indent=4, ensure_ascii=False)}"
        )
        url = f"{BASE_URL}/task/openapi/ai-app/run"
        payload = {
            "apiKey": self.api_key,
            "webappId": webapp_id,
            "nodeInfoList": node_info_list,
        }
        response = self._post_with_retry(url, json=payload)
        result = response.json()
        logger.info(f"[发起AI应用任务] 输出: {result}")
        if result.get("code") != 0:
            raise Exception(f"发起AI应用任务失败: {result.get('msg')}")
        return result.get("data", {}).get("taskId")

    def query_task(self, task_id):
        logger.info(f"[查询任务] 输入: task_id={task_id}")
        url = f"{BASE_URL}/task/openapi/status"
        payload = {"apiKey": self.api_key, "taskId": task_id}
        response = self._post_with_retry(url, json=payload)
        result = response.json()
        logger.info(f"[查询任务] 输出: {result}")
        if result.get("code") != 0:
            raise Exception(f"查询任务失败: {result.get('msg')}")
        return result.get("data")

    def get_result(self, task_id):
        logger.info(f"[获取结果] 输入: task_id={task_id}")
        url = f"{BASE_URL}/task/openapi/outputs"
        payload = {"apiKey": self.api_key, "taskId": task_id}
        response = self._post_with_retry(url, json=payload)
        result = response.json()
        logger.info(f"[获取结果] 输出: {result}")
        if result.get("code") != 0:
            # Try to extract detailed error message from data.failedReason
            exception_msg = None
            try:
                data = result.get("data")
                if data and isinstance(data, dict):
                    failed_reason = data.get("failedReason")
                    if failed_reason and isinstance(failed_reason, dict):
                        exception_msg = failed_reason.get("exception_message")
            except Exception:
                pass

            if exception_msg:
                raise Exception(exception_msg)

            raise Exception(f"获取结果失败: {result.get('msg')}")
        return result.get("data", {})


class RunninghubGenerator(BaseGenerator):
    def __init__(self, task_data: dict):
        super().__init__(task_data)
        self.current_dir = os.path.dirname(os.path.abspath(__file__))
        api_key = os.environ.get("RUNNINGHUB_API_KEY", "").strip()
        if not api_key:
            raise ValueError("RUNNINGHUB_API_KEY is required")
        self.client = RunningHubClient(api_key)

    def run_common_task(self, params):
        logger.info(
            f"[执行comfyui任务] 输入: params={json.dumps(params, indent=4, ensure_ascii=False)}"
        )

        workflow_id = params.get("workflowId")
        webapp_id = params.get("webappId")
        logger.info(f"[执行comfyui任务] 输入: workflow_id={workflow_id}, webapp_id={webapp_id}")


        node_info_list = params.get("nodeInfoList", [])

        for node in node_info_list:
            field_value = node.get("fieldValue")
            # 如果 fieldValue 是一个 URL，先下载
            if isinstance(field_value, str) and (
                field_value.startswith("http")
                or field_value.startswith("https")
                or field_value.startswith("ftp")
            ):
                self.logger.info(f"下载文件: {field_value}")
                try:
                    # 需要一个临时目录来存放下载的文件
                    temp_dir = os.path.join(self.current_dir, "temp")
                    os.makedirs(temp_dir, exist_ok=True)
                    field_value = downloadIfUrl(field_value, temp_dir)
                    self.logger.info(f"文件下载成功: {field_value}")
                except Exception as e:
                    self.logger.error(f"下载文件失败 {field_value}: {e}")
                    raise e

            # 只有当fieldName为 'video', 'image', 'audio' 时才上传
            if node.get("fieldName") in ["video", "image", "audio"] and field_value and os.path.exists(field_value):
                # 处理相对路径
                if not os.path.isabs(field_value):
                    field_value = os.path.join(self.current_dir, field_value)
                self.logger.info(f"上传文件: {field_value}")

                try:
                    uploaded_filename = self.client.upload_resource(field_value)
                    node["fieldValue"] = uploaded_filename
                    self.logger.info(f"文件上传成功: {uploaded_filename}")
                except Exception as e:
                    self.logger.error(f"上传文件失败 {field_value}: {e}")
                    raise e

        task_id = None
        if workflow_id:
            task_id = self.client.start_task(workflow_id, node_info_list).get("taskId")
        elif webapp_id:
            task_id = self.client.run_ai_app_task(webapp_id, node_info_list)
        else:
            raise Exception("任务配置错误: workflowId 或 webappId 未指定")

        if not task_id:
            raise Exception("任务启动失败")

        self.logger.info(f"任务已启动，ID: {task_id}")

        timeout = 40 * 60  # 40 minutes
        start_time = time.time()
        status = None
        retry_count = 0
        max_retry_count = 10
        last_progress_update = start_time
        progress_update_interval = 30  # Update progress every 30 seconds

        while time.time() - start_time < timeout:
            time.sleep(5)
            try:
                status = self.client.query_task(task_id)
                elapsed_time = time.time() - start_time
                self.logger.info(f"任务状态: {status} | 已运行: {elapsed_time:.1f}s")

                if status:
                    retry_count = 0 # 查询成功，重置计数器
                else:
                    retry_count += 1

                if retry_count >= max_retry_count:
                    raise Exception(f"连续{max_retry_count}次未能查询到任务状态，任务可能已丢失")

                # Update progress periodically for long-running tasks
                current_time = time.time()
                if current_time - last_progress_update >= progress_update_interval:
                    # Calculate progress based on elapsed time (30% to 60% range during execution)
                    progress_percent = min(60, 30 + int((elapsed_time / timeout) * 30))
                    self.logger.info(f"RunningHub任务进行中 | 进度: {progress_percent}% | 已运行: {elapsed_time:.1f}s")
                    last_progress_update = current_time

                if status in ["SUCCESS", "FAILED"]:
                    break
            except Exception as e:
                self.logger.warning(f"查询任务状态时出错: {e}")
                retry_count += 1
                if retry_count >= max_retry_count:
                    raise Exception(f"连续{max_retry_count}次查询任务状态失败: {e}")
        else:
            raise Exception(f"任务超时: {timeout} 秒内未完成")

        if status == "FAILED":
            result = self.client.get_result(task_id)
            raise Exception(
                f"任务失败. 详细信息: {json.dumps(result, indent=4, ensure_ascii=False)}"
            )

        result = self.client.get_result(task_id)
        self.logger.info(
            f"[执行comfyui任务] 输出: {json.dumps(result, indent=4, ensure_ascii=False)}"
        )
        return result

    def run_task(self):
        logger.info(
            f"[运行任务] 输入: task_data={json.dumps(self.task_data, indent=4, ensure_ascii=False)}"
        )
        data = self.task_data
        task_name = data.get("task")
        params = data.get("params", {})
        # workflow_id = data.get("workflow_id")
        try:
            # if not workflow_id:
            #     raise Exception("任务配置错误: workflow_id 未指定")
            result = self.run_common_task(params)
            final_result = {"result": result, "status": 0, "message": "成功"}
        except Exception as e:
            import traceback
            error_traceback = traceback.format_exc()
            self.logger.error(f"任务 '{task_name}' 失败: {e}")
            self.logger.error(f"错误堆栈:\n{error_traceback}")
            final_result = {"result": [], "status": 1, "message": str(e)}

        logger.info(
            f"[运行任务] 输出: {json.dumps(final_result, indent=4, ensure_ascii=False)}"
        )
        return final_result


if __name__ == "__main__":
    DEBUG = False
    test_data_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "/runninghub_testcases/runninghub_generator.json"
    )
    print(test_data_path)
    test_data_path = "/root/autodl-fs/allan/get_task/runninghub_testcases/runninghub_generator.json"
    test_data_path = "/root/autodl-fs/allan/get_task/workflow/毛绒玩偶头像生成.json"
    with open(test_data_path, "r") as f:
        test_data = json.load(f)

    # Create dummy files for testing if they don't exist
    # for node in test_data.get("params", {}).get("nodeInfoList", []):
    #     file_path = node.get("fieldValue")
    #     if (
    #         file_path
    #         and not os.path.exists(file_path)
    #         and not file_path.startswith("http")
    #     ):
    #         logger.info(f"创建用于测试的虚拟文件: {file_path}")
    #         with open(file_path, "w") as f:
    #             f.write("dummy content")
    test_data["params"]["nodeInfoList"][0]["fieldValue"] = "/root/autodl-fs/allan/get_task/img/8d3dbbe27f90a573541cfb093062dc027b3125.jpeg"
    # test_data["params"]["nodeInfoList"][0]["fieldValue"] = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/830acb04-6d1b-40c0-90b4-54f74fa30b2f.png"

    generator = RunninghubGenerator(test_data)
    result = generator.run_task()
    logger.info(f"最终结果: {json.dumps(result, indent=4, ensure_ascii=False)}")
    print("test-----")
