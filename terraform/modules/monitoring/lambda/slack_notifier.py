import json
import os
import urllib.request

import boto3

secretsmanager = boto3.client("secretsmanager")


def handler(event, context):
    webhook_url = secretsmanager.get_secret_value(
        SecretId=os.environ["SLACK_WEBHOOK_SECRET_ARN"]
    )["SecretString"]

    for record in event["Records"]:
        message = json.loads(record["Sns"]["Message"])
        alarm_name = message.get("AlarmName", "Unknown alarm")
        new_state = message.get("NewStateValue", "UNKNOWN")
        reason = message.get("NewStateReason", "")
        emoji = ":rotating_light:" if new_state == "ALARM" else ":white_check_mark:"

        payload = {
            "text": "{emoji} *{name}* is now *{state}*\n{reason}".format(
                emoji=emoji, name=alarm_name, state=new_state, reason=reason
            )
        }

        request = urllib.request.Request(
            webhook_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(request)
