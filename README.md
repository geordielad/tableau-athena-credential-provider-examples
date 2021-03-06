# Authenticating Tableau Users to Amazon Athena using Credential Providers

Tableau's Amazon Athena named connector supports IAM static access key credentials by default. This requires the user to supply an Access Key ID and a Secret Access Key. This has advantages when users publish content to Tableau Server because it is simple to store these credentials on the server or provide a simple prompt for Server users to enter their own credentials. This is similar to username and password support in other authentication models with the added advantage that users and applications can be provided with multiple credentials, or a single credential can be used as a service account by applications.

There are use cases where static credentials are not ideal and Amazon Athena supports other types of credentials. For example, customers may require Single Sign-On with Multi Factor Authentication for users via their standard Identity and Access Management (IAM) platform. Other customers have requirements to leverage Session Tokens that only last for a limited lifetime. Other use cases include more complex cross account scenarios and requirements to leverage AWS profiles, containers or custom credential providers.

Tableau's named connector for Amazon Athena is based on the Simba JDBC Driver and this driver has strong support for many types of authentication using a Credential Provider Interface that is provided by the AWS Java SDK. The driver supports several built-in providers and also supports the ability to add custom providers. Tableau can take advantage of this support using a JDBC properties file to use these credentials providers.

This document will how customers how to use a Tableau properties file to access the JDBC drivers built-in credential providers. I will also provide some code examples to create some simple custom providers using the AWS Java SDK to show some examples for use cases where the built-in support is not sufficient. For the built-in examples no coding is required but you may need the ability to configure a SAML IdP, have an EC2 instance, or have multiple accounts in AWS. This implies having access to a comprehensive testing environment, or the ability to coordinate with several roles across your Tableau, AWS and IAM provider platforms. We will start with the simplest scenarios that require the least amount of admin rights and tools.

## Scenario Overview

**1. The Baseline**: No customization required - Access ID and Secret Access Key. We will connect to Athena in SQL Workbench/J and Tableau using the default credentials.

**2. SQL Workbench/J Extended Properties and the Tableau JDBC Properties File**: This is more of a test to show how the various layers interact than a real use case. We will enable more detailed logging using the extended properties in SQL Workbench/J and show the equivalent properties in Tableau's *athena.properties* file.

**3. Instance Profile Credentials Provider**: This provider allows us to authenticate to Athena using the IAM Role that is tied to an EC2 Instance. This is very useful if Tableau Server is running on an EC2 Instance but it can also work if Tableau Desktop is running on the Instance. We will test both Desktop and Server. In this scenario the Athena Credentials are loaded from the Amazon EC2 Instance Metadata Service. This means that the user, or Tableau, does not need to know any secrets.

**4. AWS Security Token Service**: AWS IAM has the concept of Temporary Session Tokens. These tokens are provided by the AWS Security Token Service (STS). Several of the Credentials Providers can leverage STS directly or indirectly. STS Tokens are dynamic and temporary so they have the advantage of not being needed to be stored in a location that could be compromised.

**5. Using SAML Based Federated Access with an Identity Provider (IdP)**: Your users may not have direct access to Athena credentials but is is possible to have them authenticate via an external IdP like Okta or ADFS. In this case the JDBC driver supports the configuration of an Idp so the users pass their IdP credentials (username and password) rather than an IAM Access ID and Secret Access Key. The authentication flow is completed behind the scenes and results in a temporary session token that will allow the user to authenticate to Athena. It is important to understand that this authentication flow is via the driver without any user interaction and is therefore not able to support MFA. However it does remove the need for separate Access IDs for every Athena user.

This scenario will require IAM and IdP configuration so you will need appropriate IAM privileges and and admin rights on an IdP to complete this example. This is well documented in this [Enabling Federated Access to the Athena API Article](https://docs.aws.amazon.com/athena/latest/ug/access-federation-saml.html).

**6. Properties File Credentials Provider**: There may be situations where you want to source the credentials from some special location. This scenario may not be a good idea in a production environment but we will cover it as it will lay some foundation for the some later custom scenarios.

## Applications, Tools and Roles Requirements for each Scenario

- **AWS Account with Athena and S3 Access** - If you are reading this you should already ove access to Athena and S3 but you may need console or CLI admin access to an Athena instance for the more advanced testing. Some of the examples here would not be a good idea in a production environment but I have attempted to keep things simple as possible so make sure you are comfortable with the security implications of some of these scenarios. for the baseline and some of the tests you will need an Access ID and Secret Access Key so a test environment will be useful here. Later you will be able to apply the learnings to your production environment.

- **Amazon Athena JDBC driver** - See [Using Athena with the JDBC Driver](https://docs.aws.amazon.com/athena/latest/ug/connect-with-jdbc.html)

- **Tableau Desktop** -  We will use Tableau 2020.1

- **SQL Workbench/J** - Having access to a SQL Tool outside of Tableau that supports the Athena JDBC driver is strongly recommended. You will be able to learn from other sources of documentation as they often use SQL Workbench/J. SQL Workbench/J is free and can be downloaded from https://www.sql-workbench.eu/. I used the most current stable version as of April 2020 which was Build 125. Note you will require a Java Runtime or JDK.

- **Tableau Server**. We will use Tableau Server 2020.1. This could be a Windows or Linux version. We will need Tableau Server for all of these scenarios as they all rely on an athena properties file that will be located on the Server so Tableau Online is not an option. If the server is on an EC2 Instance you can test the Instance Profile Credential Provider but many of other scenarios will work in an On Premise Server.

- **Okta** - The JDBC driver supports authentication using external IAM platforms like ADFS and Okta that provide SAML Authentication. This is different from the IdP support provided by Tableau for User Authentication to Tableau Server but you can access the same IdP to take advantage of the capabilities that the IdP provides like federated accounts. Note that user interactive MFA is not possible via the built in JDBC driver's interfaces but there may be some non-interactive options if you are able to extend some of the custom techniques discussed later. We use Okta in this article but the concepts will be very similar for ADFS and any other IdP's that AWS supports.

- **AWS Java SDK and an Java IDE supporting Maven** - As of April 2020 the Athena JDBC driver (version 2.0.9) is built using the AWS Java SDK V1. Therefore we use the V1 SDK in some custom provider examples. I will also discuss some small issues that might force you to consider a custom provider for a feature that is built-in to the V2 SDK (this is related to leveraging profiles and credentials files) There are also some issues with the signing of JARs that need to be addressed because the JDBC driver embeds packages from the AWS Java SDK.

- **A Second AWS Account** - A second account with Athena will allow us to test cross account role assumption scenarios. In these Scenarios Tableau Server may be installed in an EC2 Instance under onw account while Athena is installed in another account. When using static credentials this is not a problem but if you want to rely on some of the more advanced scenarios, like the Instance Profile Credentials Provider, you will need to be able to set up the right IAM Roles.

- **Athena with a non-primary Workgroup** - This is not strictly a credentials issue but we can use the Tableau JDBC properties file to select non-primary Workgroups. This can be useful for customers leveraging Athena Workgroups to manage access Athena at scale.

## Detailed Scenarios

### 1. The Baseline

- **SQL Workbench**: Follow the documentation in the [Simba Athena JDBC Driver Installation and Configuration Guide](https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC_2.0.9/docs/Simba+Athena+JDBC+Driver+Install+and+Configuration+Guide.pdf). Simply follow the instructions in the **Installing and Using the Simba Athena JDBC Driver section**.
  
- **Tableau Desktop**: Follow the documentation in the Tableau Desktop Help Topic [Amazon Athena](https://help.tableau.com/current/pro/desktop/en-us/examples_amazonathena.htm). Use the same settings you used in the SQL Workbench/J test.
  
    ![Tableau Desktop Example](https://help.tableau.com/current/pro/desktop/en-us/Img/examples_amazonathena.png)

### 2. SQL Workbench/J Extended Properties and the Tableau Properties File

- **SQL Workbench/J**: You have already used an extended property in the baseline scenario to enter the S3 Bucket for the Athena result set so feel free to skip this step but if you want to see how we can map SQL Workbench/J extended properties to the Tableau Properties this exercise will also help you set up logging for troubleshooting purposes. You have already used extended properties in SQL Workbench/J for the Athena result set bucket in S3. We just need to add the logging properties. These properties are documented in the [Athena JDBC Driver Installation and Configuration Guide](https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC_2.0.9/docs/Simba+Athena+JDBC+Driver+Install+and+Configuration+Guide.pdf):

    ![SQL Workbench/J Logging Properties](img/sql-workbench-logging-properties.jpg)

    After setting your extended properties enter your ID and Key and test the connection. You should see some log files created in the log folder.

    ![Athena Log Files](img/athena-log-files.jpg)

- **Tableau**: The S3 result set bucket is not a special property for Tableau but everything else we will cover in this article will require a properties file on Desktop, or Server, so let's get started by enabling the same detailed logging as SQL Workbench/J.

    On Tableau Desktop you will need to create an *athena.properties* file in your Tableau Repository Datasources folder. This is described in more detail in the [Customizing JDBC Connections KB Article](https://kb.tableau.com/articles/howto/Customizing-JDBC-Connections). To enable detailed logging the properties file will contain several key/value settings. Note that the key names and values are exactly the same as you entered in SQL Workbench. ([example](property-file-examples/scenario-2/athena.properties)):

    ```
    loglevel=6
    logpath=c:/athena-jdbc-logs
    UseAwsLogger=1
    ```

    Once you enable logging on the driver and perform a test connection and and query you will see some log files created in the logging folder.

    ![Athena Log Files](img/athena-log-files-2.jpg)

    If you are troubleshooting the useful information is usually in the connection file. and you will often see multiple connection files created during your testing. If you are testing SQL Workbench and Tableau at the same time you may want to put the log files in different folders.

### 3. Instance Profile Credentials Provider

If your Tableau Server is installed on an AWS EC2 Instance you can use the IAM Instance Profile to authenticate to Athena. This has significant advantages in that no user that are consuming published workbooks or shared data connection need any Athena Credentials at any time. The permissions to Athena will be controlled by your AWS administrator.

The configuration for SQL Workbench/J and Tableau is very easy now that you know how to use SQL Workbench/J and Tableau properties. For Tableau Server on the EC2 Instance side you only need the athena.properties file to be added to the Tableau Server's Datasources folder (```tabsvc/vizlserver/Datasources``` for Windows or ```/var/opt/tableau/tableau_server/data/tabsvc/vizqlserver/Datasources/``` for Linux).
    
On the SQL Workbench/J and Tableau side you can follow the [Athena JDBC Driver Installation and Configuration Guide](https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC_2.0.9/docs/Simba+Athena+JDBC+Driver+Install+and+Configuration+Guide.pdf) (See the Section on *Using InstanceProfileCredentialsProvider* on page 35.
    
- **SQL Workbench/J**:
    
    **Note:** You will need to be running SQL Workbench on the EC2 Instance.
    
    ![Workbench/J Instance profile Credentials Extended Properties](img/workbech-instance-profile-properties.jpg)
    
- **Tableau Server**:  
    
    ([Tableau athena.properties file for Instance Profile Credentials](property-file-examples/scenario-3/athena.properties))
    
    ```
    AwsCredentialsProviderClass=com.simba.athena.amazonaws.auth.InstanceProfileCredentialsProvider
    AWSRegion=us-east-1
    S3OutputLocation=s3://aws-athena-query-results-XXXXXXXX-us-east-1/
    RowsToFetchPerBlock=10000
    LogPath=c:/athena-jdbc-logs
    LogLevel=6
    UseAwsLogger=1
    ```
    
    As documented in the Driver guide, you will need to associate an IAM Role to the EC2 Instance that is hosting Tableau Server. If the Tableau instance is a cluster then attach the role to each node in the cluster. The steps on the AWS side are documented in the [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) article.
    
    On my EC2 Instance I created a role and configured that role to allow access to Athena and S3:
    
    ![EC2 Instance Profile Role](img/ec2-instance-iam-role.jpg)

    In the IAM Console the Role looks like this:

    ![IAM Instance Profile Role](img/iam-instance-profile-role.jpg)
    
    As long as the role has appropriate access to Athena and S3 then SQL Workbench and Tableau will be able to utilize the Instance Profile to acquire the credentials for Athena. But first we need to publish some content from Tableau Desktop and I am going to assume that your Tableau Desktop is not on an EC2 instance. This means that we cannot use the Instance Profile Credentials scenario we will need to use another technique. Don't worry, later in this article we will see some options for allowing the Desktop authentication to not rely on static credentials but right now lets create some content on Tableau Desktop using a Static ID and Access Key and then publish to our server that if configured for Instance Profile Credentials.

#### 1. Create a New Workbook with a Connection to Athena

**Note**: this is a Tableau Desktop that is **not** on our EC2 Instance

![Desktop Connection](img/tableau-desktop-connect-to-athena.jpg)

#### 2. Create some Content

![Desktop Create Content](img/tableau-desktop-connect-to-athena-2.jpg)

![Desktop Create Content](img/tableau-desktop-connect-to-athena-3.jpg)

#### 3. Publish the Workbook (or the Data Source) to Tableau Server

We will publish the Data Source so we can access it later using the profile Credentials. Note that we can either embed the password or leave it a prompt user. We will remove the username and any password after publishing so its not that important.

![Desktop Publish](img/tableau-desktop-connect-to-athena-4.jpg)

#### 4. Update the Username and Password to dummy values

You need to enter something to enable the Sign-In or Save button.

![Server Update Connection Information](img/tableau-desktop-connect-to-athena-7.jpg)

#### 5. Your Connection is now saved

It should be using the Instance Profile Credentials to authenticate to Athena.

![Server Update Connection Information](img/tableau-desktop-connect-to-athena-8.jpg)

#### 6. You can now create content on Server and Desktop using the Published Connection without needing any credentials

![Server Update Connection Information](img/tableau-desktop-connect-to-athena-8a.jpg)

![Server Update Connection Information](img/tableau-desktop-connect-to-athena-9.jpg)

### 4. AWS Security Token Service

The [AWS Security Token Service](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html) is a general purpose Web Service for temporary, and limited-privilege, credentials that can be used for Athena to avoid creating and sharing static credentials. Athena can use STS Tokens, often referred to as Session Tokens or Temporary Tokens, to authenticate via the JDBC Driver. STS Tokens cannot be passed directly in the JDBC Connection string or extended properties - therefore they are not passed directly in Tableau's _athena.properties_ file. This is because an STS credential consists of an Access Key ID, a Secret Access Key **and** a Session Token. STS credentials can be created by several mechanisms including the AWS CLI, the SDK Credentials Providers and Custom Providers. Here we will explore some of the techniques. Which one is best for your use case will depend on how much integration you need with your IAM, Directory or Federation Platform.

We will start by using some simple mechanisms for acquiring the STS Credentials so we can focus on how Tableau Desktop can use the credentials. Note that these simple mechanisms are not intended for production use. First we will use the simplest AWS CLI STS method called GetSessionToken. The problem with this method (in the way we will be using it) is that it requires the caller to already be an AWS IAM user. This looks like a problem because the whole point of the STS Service is to avoid the need for static credentials, but remember we are focusing on how Tableau will *use* the token. Later we will look at some techniques for using a Secure Service to request the tokens, and deliver them to Tableau Desktop.

To get started we will use a method that is really designed for Multi-Factor Authentication (MFA). This method is called GetSessionToken.

Let's get Started:

#### 1. Request a Session Token using the AWS CLI

We need to call GetSessionToken using the credentials of an IAM User that already has access to Athena. This is because the temporary STS credentials will have the same permissions as the IAM User. If you as an individual do not have these rights or do not have access to the CLI you will need to get assistance from someone that can provide you with the credentials. You will see all they need to do is provide the Access Key ID, Secret Key and Session Token.

The cli command is:

```aws sts get-session-token --duration-seconds 3600 --output json```

The full documentation for the cli command is at [https://docs.aws.amazon.com/cli/latest/reference/sts/get-session-token.html]

Here we requested the token with a lifetime of 3600 seconds or one hour.

The Output will be like this:

```
    {
        "Credentials": {
            "AccessKeyId": "ASIA3ZJR2NTIR3ZVUJ3Q",
            "SecretAccessKey": "Cg0zgZtN5VbzByDwFHbtLDd/h+fR8NFNSdkWCJcO",
            "SessionToken": "FwoGZXIvYXdzEJj//////////wEaDMkYX79x40KQdH2K4yKBAebqs3uhgE+hrwfCOmV8ruJkb7/YIZMCfIuDUi3Jz84+DEu1VOpVQ3g75CvW36SN0gvX2qTDncOQIie39Nd7faEPjCLMtMfu2aTdBkFCq0Fa42lcukouPc+q3f5E1PVaoniFgSW7i6Oqp3OV1H3s9pULtIUZdBUzy1zyYZvXFmRGMCi5jPn2BTIoKUxvRObf/0sX0wA/IpvPlkgM6MrCtungUbgmdAyl7suelc81Flse7g==",
            "Expiration": "2020-06-08T15:07:53Z"
        }
    }
```

#### 2. Pass the STS Credentials to Tableau Desktop

Once you get these credentials you will need to pass them to them to Tableau Desktop, You cannot pass them directly in the *athena.properties* file but you tell the properties file where to find the credentials.

Place this [*athena.properties*](property-file-examples/scenario-4/athena.properties) file in your Tableau DataSources folder (usually *My Tableau Repository\Datasources* in your Documents folder)

```
    AwsCredentialsProviderClass=com.simba.athena.amazonaws.auth.DefaultAWSCredentialsProviderChain
```

This properties file is telling the JDBC driver to look for the credentials in a series of providers using a specific order of precedence. The [AWS SDK Documentation](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) describes the order that is used in more detail. The order is:

1. **Environment variables**
2. **Java system variables**
3. **The default credential profiles file**
4. **Amazon ECS container credentials**
5. **Instance profile credentials**

For Tableau Desktop the best options are **1.** or **2.**

You can use a helper script, or program, to define the variables, then launch Tableau Desktop. For example here is a Windows Powershell script that used the credentials created in the example above:

```
    $env:AWS_ACCESS_KEY_ID = "ASIA3ZJR2NTIR3ZVUJ3Q"

    $env:AWS_SECRET_ACCESS_KEY = "Cg0zgZtN5VbzByDwFHbtLDd/h+fR8NFNSdkWCJcO"

    $env:AWS_SESSION_TOKEN  = "FwoGZXIvYXdzEJj//////////wEaDMkYX79x40KQdH2K4yKBAebqs3uhgE+hrwfCOmV8ruJkb7/YIZMCfIuDUi3Jz84+DEu1VOpVQ3g75CvW36SN0gvX2qTDncOQIie39Nd7faEPjCLMtMfu2aTdBkFCq0Fa42lcukouPc+q3f5E1PVaoniFgSW7i6Oqp3OV1H3s9pULtIUZdBUzy1zyYZvXFmRGMCi5jPn2BTIoKUxvRObf/0sX0wA/IpvPlkgM6MrCtungUbgmdAyl7suelc81Flse7g=="

    Start-Process -FilePath "C:\Program Files\Tableau\Tableau 2020.1\bin\tableau.exe" -WorkingDirectory "C:\Program Files\Tableau\Tableau 2020.1"
```
Note how we copied the exact quoted strings from the JSON file into our Powershell Script.

If you are able to test this on a workstation that has Tableau Desktop installed I have created a [helper Powershell script](shell-script-examples/scenario-4/get-sts-credentials.ps1). The script calls the AWS CLI, defines the environment variables and launches Tableau Desktop without the need to edit any files (You will need to to edit the path to the Tableau Desktop program in the script).

#### 3. Connect to Athena and Build the Viz

Because you are using the *athena.properties* file to handle the credentials you cn put anything in the Access Key ID field. You only need to put something there to enable the *Sign In* button.

![Connect to Athena](img/2020-06-08-17-05-44.png)

#### 4. Publish the Workbook or Connection to Tableau Server

The STS credentials you just used are temporary and they will **not** be saved on Tableau Server. But you can take advantage of an *athena.properties* file on Tableau Server to get SSO to Athena for consumers of the published Workbook or Shared Connection. If your Tableau Server is running on an EC2 Instance you can use the Instance Credentials provider approach described in **Scenario 3.**
